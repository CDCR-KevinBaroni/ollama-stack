#!/usr/bin/env bash
# Re-apply the Tavily client patch after a 'pip install -U open-webui' upgrade
# has clobbered the vendored file. Idempotent: re-running over an already
# patched copy is a no-op.
#
# Source of truth:  <repo>/systemd/patches/tavily.py
# Destination:      /opt/open-webui/venv/lib/python3.11/site-packages/
#                       open_webui/retrieval/web/tavily.py
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SCRIPT_DIR}/tavily.py"
DST=/opt/open-webui/venv/lib/python3.11/site-packages/open_webui/retrieval/web/tavily.py
BACKUP="${DST}.bak-$(date +%Y%m%d-%H%M%S)"

if [[ ! -f "$SRC" ]]; then
    echo "ERROR: patched source not found at $SRC" >&2
    exit 1
fi
if [[ ! -f "$DST" ]]; then
    echo "ERROR: destination not found at $DST (is Open WebUI installed at /opt/open-webui/venv?)" >&2
    exit 1
fi

if cmp -s "$SRC" "$DST"; then
    echo "tavily.py already patched (no change)."
    exit 0
fi

echo "Backing up unpatched destination -> $BACKUP"
sudo cp "$DST" "$BACKUP"

echo "Installing patched tavily.py -> $DST"
sudo install -m 0644 -o root -g root "$SRC" "$DST"

echo "Restarting open-webui to load the patched module"
sudo systemctl restart open-webui

echo "Done. Verify with: sudo grep -E \"topic|days|include_answer|Tavily synthesized\" $DST"
