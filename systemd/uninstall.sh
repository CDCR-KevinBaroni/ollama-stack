#!/usr/bin/env bash
# uninstall.sh -- reverse install.sh.
#
# Removes unit files and the ollama drop-in override. Stops and disables
# managed units. Leaves user data (/var/lib/ollama, /var/lib/open-webui) and
# /etc/default/open-webui in place; remove those manually if you want a
# clean slate.
#
# Does NOT uninstall Ollama itself or the Open WebUI venv.

set -euo pipefail

ETC_SYSTEMD="/etc/systemd/system"
OLLAMA_DROPIN="${ETC_SYSTEMD}/ollama.service.d/override.conf"
OLLAMA_DROPIN_DIR="${ETC_SYSTEMD}/ollama.service.d"

log()  { printf '[uninstall] %s\n' "$*"; }
warn() { printf '[uninstall] WARN: %s\n' "$*" >&2; }
die()  { printf '[uninstall] ERROR: %s\n' "$*" >&2; exit 1; }

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        die "must run as root (try: sudo $0)"
    fi
}

stop_units() {
    log "stopping and disabling managed units"
    # `|| true` because absent or already-disabled units must not fail us.
    systemctl disable --now open-webui.service 2>/dev/null || true
    systemctl disable --now ollama-warmup.service 2>/dev/null || true
    # Leave ollama.service running -- it was installed by the upstream
    # installer, not by us. Just strip our override.
}

remove_files() {
    log "removing open-webui.service"
    rm -f "${ETC_SYSTEMD}/open-webui.service"

    log "removing ollama-warmup.service"
    rm -f "${ETC_SYSTEMD}/ollama-warmup.service"

    if [[ -f "${OLLAMA_DROPIN}" ]]; then
        log "removing ollama drop-in override"
        rm -f "${OLLAMA_DROPIN}"
        # rmdir is safe: only removes if empty
        rmdir "${OLLAMA_DROPIN_DIR}" 2>/dev/null || true
    fi
}

reload_and_restart_ollama() {
    log "systemctl daemon-reload"
    systemctl daemon-reload

    if systemctl is-active --quiet ollama.service; then
        log "restarting ollama to drop the override tuning"
        systemctl restart ollama.service
    fi
}

main() {
    require_root
    stop_units
    remove_files
    reload_and_restart_ollama
    warn "user data preserved at /var/lib/ollama and /var/lib/open-webui"
    warn "EnvironmentFile preserved at /etc/default/open-webui"
    log "done."
}

main "$@"
