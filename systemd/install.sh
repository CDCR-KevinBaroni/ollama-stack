#!/usr/bin/env bash
# install.sh -- wire the systemd/ folder into /etc/systemd/system and start
# the units. Idempotent: re-runs are safe.
#
# What this DOES:
#   * Verifies prerequisites (ollama binary, open-webui venv, ollama user)
#   * Creates /var/lib/ollama/models and /var/lib/open-webui with correct
#     ownership
#   * Installs the ollama drop-in override
#   * Installs open-webui.service and ollama-warmup.service
#   * Seeds /etc/default/open-webui from the .example if missing
#   * daemon-reload, enable --now, and status
#
# What this does NOT do:
#   * Install Ollama (run: curl -fsSL https://ollama.com/install.sh | sh)
#   * Install Open WebUI venv (see README.md "One-time prerequisites")
#   * Migrate model files from /mnt/d/ (see MIGRATION.md)
#   * Configure the Tavily API key (edit /etc/default/open-webui after install)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ETC_SYSTEMD="/etc/systemd/system"
OLLAMA_DROPIN_DIR="${ETC_SYSTEMD}/ollama.service.d"
OPEN_WEBUI_VENV="/opt/open-webui/venv"
OLLAMA_DATA_DIR="/var/lib/ollama"
OPEN_WEBUI_DATA_DIR="/var/lib/open-webui"
ENV_FILE="/etc/default/open-webui"

log()  { printf '[install] %s\n' "$*"; }
warn() { printf '[install] WARN: %s\n' "$*" >&2; }
die()  { printf '[install] ERROR: %s\n' "$*" >&2; exit 1; }

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        die "must run as root (try: sudo $0)"
    fi
}

require_prereqs() {
    command -v ollama >/dev/null \
        || die "ollama not installed. Run: curl -fsSL https://ollama.com/install.sh | sh"
    id ollama >/dev/null 2>&1 \
        || die "ollama user not present (the official installer creates it). Re-run the installer."

    if [[ ! -x "${OPEN_WEBUI_VENV}/bin/open-webui" ]]; then
        warn "open-webui not found at ${OPEN_WEBUI_VENV}/bin/open-webui"
        warn "see README.md 'One-time prerequisites' for venv setup. Continuing -- open-webui.service will fail until the venv exists."
    fi

    if ! id open-webui >/dev/null 2>&1; then
        warn "open-webui system user does not exist; creating it"
        useradd --system --home-dir "${OPEN_WEBUI_DATA_DIR}" --shell /usr/sbin/nologin open-webui
    fi
}

prepare_dirs() {
    log "creating ${OLLAMA_DATA_DIR}/models"
    install -d -o ollama -g ollama -m 0755 "${OLLAMA_DATA_DIR}"
    install -d -o ollama -g ollama -m 0755 "${OLLAMA_DATA_DIR}/models"

    log "creating ${OPEN_WEBUI_DATA_DIR}"
    install -d -o open-webui -g open-webui -m 0755 "${OPEN_WEBUI_DATA_DIR}"
}

install_units() {
    log "installing ollama drop-in override -> ${OLLAMA_DROPIN_DIR}/override.conf"
    install -d -m 0755 "${OLLAMA_DROPIN_DIR}"
    install -m 0644 "${SCRIPT_DIR}/ollama.service.d-override.conf" "${OLLAMA_DROPIN_DIR}/override.conf"

    log "installing open-webui.service"
    install -m 0644 "${SCRIPT_DIR}/open-webui.service" "${ETC_SYSTEMD}/open-webui.service"

    log "installing ollama-warmup.service"
    install -m 0644 "${SCRIPT_DIR}/ollama-warmup.service" "${ETC_SYSTEMD}/ollama-warmup.service"
}

seed_env_file() {
    if [[ -e "${ENV_FILE}" ]]; then
        log "${ENV_FILE} already exists -- leaving it alone"
    else
        log "seeding ${ENV_FILE} from open-webui.env.example"
        install -m 0640 -o root -g open-webui "${SCRIPT_DIR}/open-webui.env.example" "${ENV_FILE}"
        warn "edit ${ENV_FILE} to set TAVILY_API_KEY, then: systemctl restart open-webui"
    fi
}

reload_and_enable() {
    log "systemctl daemon-reload"
    systemctl daemon-reload

    log "enabling units"
    systemctl enable ollama.service ollama-warmup.service open-webui.service

    # NOTE: `enable --now` does not restart an already-running ollama.service, so a
    # running daemon would not pick up env changes from the override drop-in (e.g.
    # OLLAMA_MODELS). Always explicitly restart ollama, then start the dependents
    # in order so the warmup hits a daemon that has already loaded the override.
    log "restarting ollama (to apply override drop-in if daemon was already up)"
    systemctl restart ollama.service

    log "starting ollama-warmup (preloads warm models)"
    systemctl restart ollama-warmup.service

    log "starting open-webui"
    systemctl restart open-webui.service
}

status() {
    log "status:"
    systemctl --no-pager --full status ollama ollama-warmup open-webui || true
}

main() {
    require_root
    require_prereqs
    prepare_dirs
    install_units
    seed_env_file
    reload_and_enable
    status
    log "done. Verify with: curl -s http://127.0.0.1:11434/api/ps | jq"
}

main "$@"
