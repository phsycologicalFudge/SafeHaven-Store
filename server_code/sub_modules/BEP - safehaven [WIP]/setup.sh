#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo "[setup] $*"; }
die() { echo "[error] $*" >&2; exit 1; }

[ "$EUID" -eq 0 ] || die "run this script as root: sudo bash setup.sh"

log "--- system deps ---"
apt-get update -qq
apt-get install -y -qq docker.io unzip curl git python3 python3-pip

log "--- enabling systemd for WSL ---"
WSL_CONF="/etc/wsl.conf"
if grep -q "systemd=true" "$WSL_CONF" 2>/dev/null; then
    log "systemd already enabled"
else
    cat >> "$WSL_CONF" << 'EOF'

[boot]
systemd=true
EOF
    log "systemd enabled"
fi

log "--- docker group ---"
groupadd -f docker
usermod -aG docker "$SUDO_USER"
log "added $SUDO_USER to docker group"

log ""
log "setup complete."
log "NEXT: run 'wsl --shutdown' from PowerShell, then reopen WSL"
log "after restart: docker build -t bep-runner $SCRIPT_DIR"
log "then from Windows: python main.py <github_url>"
