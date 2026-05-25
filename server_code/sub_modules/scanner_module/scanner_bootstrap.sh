#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
HASH_SERVER_DIR="$SCRIPT_DIR/hash_server"
ENGINE_DIR="$SCRIPT_DIR/optional_engine"
VENV_DIR="$SCRIPT_DIR/.venv"
SCANNER_PORT="8080"
HASH_PORT="8081"
PYTHON_BIN="python3"
FORCE_RESCAN="${FORCE_RESCAN:-0}"
WORKER_SECRET="fdroid-scraper-secret"

for arg in "$@"; do
  case "$arg" in
    --force-rescan)
      FORCE_RESCAN="1"
      ;;
  esac
done

cd "$SCRIPT_DIR"

apt-get update
apt-get install -y python3 python3-venv python3-pip apksigner aapt2 \
  || apt-get install -y python3 python3-venv python3-pip android-sdk-build-tools

APKSIGNER_PATH="$(command -v apksigner 2>/dev/null || true)"
if [ -z "$APKSIGNER_PATH" ]; then
  APKSIGNER_PATH="$(find /usr -name apksigner 2>/dev/null | head -n 1 || true)"
fi
if [ -z "$APKSIGNER_PATH" ]; then
  echo "apksigner not found"
  exit 1
fi

AAPT2_PATH="$(command -v aapt2 2>/dev/null || true)"
if [ -z "$AAPT2_PATH" ]; then
  AAPT2_PATH="$(find /usr -name aapt2 2>/dev/null | head -n 1 || true)"
fi
if [ -z "$AAPT2_PATH" ]; then
  echo "aapt2 not found"
  exit 1
fi

if [ ! -d "$VENV_DIR" ]; then
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

source "$VENV_DIR/bin/activate"

pip install --upgrade pip
pip install fastapi uvicorn httpx pydantic

cat > "$SCRIPT_DIR/.env" <<EOF
CS_API_URL="https://api.colourswift.com"
VPS_AUTH_SECRET="enter-your-secret"
POLL_INTERVAL="30"
FORCE_RESCAN="$FORCE_RESCAN"
APKSIGNER_BIN="$APKSIGNER_PATH"
AAPT2_BIN="$AAPT2_PATH"
ENGINE_ENABLED="1"
VXTITANIUM_LIB_PATH="$ENGINE_DIR/lib/libcolourswift_av.so"
VXTITANIUM_DEFS_PATH="$ENGINE_DIR/defs"
TFLITE_LIB_PATH="$ENGINE_DIR/lib/libtensorflowlite_c.so"
HASH_API_URL="http://127.0.0.1:$HASH_PORT/check_batch"
HASH_API_KEY="23JVO3ojo23oO3O423rrTR"
EOF

cat > "$SCRIPT_DIR/.env.hash" <<EOF
CS_SECRET="23JVO3ojo23oO3O423rrTR"
BAZAAR_INTERVAL="7200"
CS_IOC_DIR="$HASH_SERVER_DIR/raw_database/iocs"
EOF

cat > /etc/systemd/system/safehaven-hash.service <<EOF
[Unit]
Description=SafeHaven Hash Server
After=network.target

[Service]
Type=simple
WorkingDirectory=$HASH_SERVER_DIR
EnvironmentFile=$SCRIPT_DIR/.env.hash
ExecStart=$VENV_DIR/bin/uvicorn server:app --host 127.0.0.1 --port $HASH_PORT --workers 1
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/safehaven-defs.service <<EOF
[Unit]
Description=SafeHaven AV Definitions Updater
After=network.target

[Service]
Type=simple
WorkingDirectory=$SCRIPTS_DIR
Environment=DEFS_DIR=$ENGINE_DIR/defs
Environment=DEFS_UPDATE_INTERVAL=86400
ExecStart=$VENV_DIR/bin/python3 defs_updater.py
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/safehaven-scanner.service <<EOF
[Unit]
Description=SafeHaven APK Scanner
After=network.target safehaven-hash.service

[Service]
Type=simple
WorkingDirectory=$SCRIPTS_DIR
EnvironmentFile=$SCRIPT_DIR/.env
ExecStart=$VENV_DIR/bin/uvicorn safehaven_scanner:app --host 0.0.0.0 --port $SCANNER_PORT --workers 1
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/safehaven-fdroid.service <<EOF
[Unit]
Description=SafeHaven F-Droid Index Syncer
After=network.target

[Service]
Type=simple
WorkingDirectory=$SCRIPTS_DIR
Environment=WORKER_SECRET=$WORKER_SECRET
ExecStart=/bin/bash -c "while true; do $VENV_DIR/bin/python3 fdroid_push_script.py; sleep 3600; done"
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

systemctl enable safehaven-hash
systemctl restart safehaven-hash
systemctl status safehaven-hash --no-pager

systemctl enable safehaven-defs
systemctl restart safehaven-defs
systemctl status safehaven-defs --no-pager

systemctl enable safehaven-scanner
systemctl restart safehaven-scanner
systemctl status safehaven-scanner --no-pager

systemctl enable safehaven-fdroid
systemctl restart safehaven-fdroid
systemctl status safehaven-fdroid --no-pager