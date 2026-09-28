#!/usr/bin/env bash
# Smoke QA local de JUST4FOLDERS: build + tests + arranque + comprobaciones AX mínimas.
# Complementa a QA_LOCAL.md (checklist manual); no sustituye a la validación de campo.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

LOG_FILE="$HOME/Library/Logs/JUST4FOLDERS/just4folders.log"

echo "[1/5] Build (debug)…"
swift build

echo "[2/5] Tests unitarios…"
swift test 2>&1 | tail -4

echo "[3/5] Relanzando la app (registro en $LOG_FILE)…"
pkill -x JUST4FOLDERS 2>/dev/null || true
sleep 1
nohup .build/debug/JUST4FOLDERS >/tmp/j4f-qa-run.log 2>&1 &
sleep 4

if ! pgrep -x JUST4FOLDERS >/dev/null; then
    echo "ERROR: la app no arrancó (revisa /tmp/j4f-qa-run.log)."
    exit 1
fi
echo "  app en marcha (pid $(pgrep -x JUST4FOLDERS | head -1))."

echo "[4/5] Comprobaciones AX mínimas…"
osascript -e 'tell application "System Events" to tell process "JUST4FOLDERS" to get name of every window' >/dev/null
PLACEHOLDER=$(osascript -e 'tell application "System Events" to tell process "JUST4FOLDERS" to return (value of attribute "AXPlaceholderValue" of text field 1 of group 1 of toolbar 1 of window 1)')
echo "  buscador: $PLACEHOLDER"
if ! printf '%s' "$PLACEHOLDER" | grep -qE "carpeta|ndice"; then
    echo "ERROR: placeholder de busqueda inesperado."
    exit 1
fi

echo "[5/5] Trazas recientes del registro (últimas 3):"
tail -3 "$LOG_FILE" || true

echo "[j4f] Smoke OK. La app queda en marcha (pkill -x JUST4FOLDERS para cerrarla)."
