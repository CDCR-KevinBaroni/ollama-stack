#!/usr/bin/env bash
# tune-threads.sh -- sweep OLLAMA_NUM_THREADS to find the optimum for this CPU.
#
# Why: the value "4" baked into ollama.service.d-override.conf is the right
# default for an Intel hybrid CPU with 4 P-cores (i7-1360P), but the optimum
# can land at 2, 4, 6, or 8 depending on workload, kernel scheduler, and
# whether HT siblings help. This script measures it directly.
#
# Method: for each candidate N, sets OLLAMA_NUM_THREADS=N on a temporary
# override, restarts ollama, sends a fixed prompt, records eval_count /
# eval_duration (tokens per second), then restores the original override.
# Picks the N with the highest tok/s and prints a suggested override.
#
# Requires: jq, curl, sudo (to write the override and restart ollama).
# Run from anywhere; uses /etc/systemd/system/ollama.service.d/override.conf
# and a sibling backup file.

set -euo pipefail

MODEL="${MODEL:-llama3.2:3b}"
PROMPT="${PROMPT:-Write a one-paragraph summary of how mmap works.}"
THREAD_VALUES=(${THREAD_VALUES:-2 4 6 8})
WARMUP_RUNS="${WARMUP_RUNS:-1}"
TIMED_RUNS="${TIMED_RUNS:-3}"

OVERRIDE_DIR="/etc/systemd/system/ollama.service.d"
OVERRIDE="${OVERRIDE_DIR}/override.conf"
BACKUP="${OVERRIDE_DIR}/override.conf.tune-backup"

log() { printf '[tune] %s\n' "$*"; }
die() { printf '[tune] ERROR: %s\n' "$*" >&2; exit 1; }

require_prereqs() {
    command -v jq >/dev/null    || die "jq not installed"
    command -v curl >/dev/null  || die "curl not installed"
    [[ "${EUID}" -eq 0 ]]       || die "must run as root (sudo)"
    [[ -f "${OVERRIDE}" ]]      || die "override not found at ${OVERRIDE}; run install.sh first"
}

backup_override() {
    cp "${OVERRIDE}" "${BACKUP}"
    log "backed up override -> ${BACKUP}"
}

restore_override() {
    if [[ -f "${BACKUP}" ]]; then
        mv "${BACKUP}" "${OVERRIDE}"
        systemctl daemon-reload
        systemctl restart ollama
        log "restored original override and restarted ollama"
    fi
}
trap restore_override EXIT

set_threads() {
    local n="$1"
    # Replace the OLLAMA_NUM_THREADS line in the override file in place.
    sed -i -E "s|^Environment=\"OLLAMA_NUM_THREADS=.*\"|Environment=\"OLLAMA_NUM_THREADS=${n}\"|" "${OVERRIDE}"
    systemctl daemon-reload
    systemctl restart ollama
    # Wait for /api/tags to respond.
    for _ in $(seq 1 30); do
        if curl -sf http://127.0.0.1:11434/api/tags >/dev/null; then return 0; fi
        sleep 1
    done
    die "ollama did not come back up with NUM_THREADS=${n}"
}

run_once() {
    # Returns tokens-per-second for one /api/generate call.
    local resp eval_count eval_duration tok_per_sec
    resp="$(curl -s http://127.0.0.1:11434/api/generate \
        -d "$(jq -n --arg m "${MODEL}" --arg p "${PROMPT}" \
              '{model:$m, prompt:$p, stream:false}')")"
    eval_count="$(echo "${resp}"    | jq -r '.eval_count // empty')"
    eval_duration="$(echo "${resp}" | jq -r '.eval_duration // empty')"
    if [[ -z "${eval_count}" || -z "${eval_duration}" || "${eval_duration}" == "0" ]]; then
        echo "0"
        return
    fi
    # eval_duration is in nanoseconds.
    tok_per_sec="$(awk -v c="${eval_count}" -v d="${eval_duration}" 'BEGIN{ printf "%.2f", (c / (d / 1e9)) }')"
    echo "${tok_per_sec}"
}

best_n=""
best_tps="0"
declare -A results

main() {
    require_prereqs
    log "model=${MODEL}  values=${THREAD_VALUES[*]}  timed_runs=${TIMED_RUNS}"
    backup_override

    for n in "${THREAD_VALUES[@]}"; do
        log "------ OLLAMA_NUM_THREADS=${n} ------"
        set_threads "${n}"

        # Warm the model so we measure inference, not load.
        for i in $(seq 1 "${WARMUP_RUNS}"); do
            run_once >/dev/null
        done

        local sum="0" tps
        for i in $(seq 1 "${TIMED_RUNS}"); do
            tps="$(run_once)"
            log "  run ${i}: ${tps} tok/s"
            sum="$(awk -v s="${sum}" -v t="${tps}" 'BEGIN{ printf "%.2f", s+t }')"
        done
        local avg
        avg="$(awk -v s="${sum}" -v n="${TIMED_RUNS}" 'BEGIN{ printf "%.2f", s/n }')"
        results["${n}"]="${avg}"
        log "  AVG: ${avg} tok/s"

        if awk -v a="${avg}" -v b="${best_tps}" 'BEGIN{ exit !(a > b) }'; then
            best_tps="${avg}"
            best_n="${n}"
        fi
    done

    echo
    log "===== summary (tokens/sec, higher = better) ====="
    for n in "${THREAD_VALUES[@]}"; do
        printf '  NUM_THREADS=%-3s %s tok/s\n' "${n}" "${results[${n}]}"
    done
    echo
    log "winner: OLLAMA_NUM_THREADS=${best_n} at ${best_tps} tok/s"
    log "to make permanent, set this in ollama.service.d-override.conf and re-run install.sh"
}

main "$@"
