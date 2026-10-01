#!/bin/sh
# Apunta LIFEOS al servidor local de LifeOS y lo lanza (flujo de desarrollo).
#
#   ./scripts/dev_local.sh                 # usa http://127.0.0.1:8000
#   ./scripts/dev_local.sh http://192.168.100.15:8000
#
# El servidor local sale del compose del repo de LifeOS:
#   cd ../0_server_dorticos/LifeOS && docker compose up -d
#
# Credenciales de desarrollo del compose: `owner` / `change-me-in-dev`.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BASE_URL="${1:-http://127.0.0.1:8000}"
BUNDLE_ID="com.dmx83.lifeos"
APP_PATH="$PROJECT_ROOT/build/Build/Products/Release/LIFEOS.app"

# 1) ¿Está el servidor?
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$BASE_URL/health/ready" || echo 000)
if [ "$CODE" != "200" ]; then
  echo "El servidor de LifeOS no responde en $BASE_URL (código $CODE)."
  echo "Levántalo con: cd ../0_server_dorticos/LifeOS && docker compose up -d"
  exit 1
fi
echo "Servidor local OK en $BASE_URL"

# 2) Que la app arranque apuntando ahí (UserDefaults de la app).
defaults write "$BUNDLE_ID" lifeos.baseURL "$BASE_URL"
echo "Dirección guardada: $(defaults read "$BUNDLE_ID" lifeos.baseURL)"

# 3) Lanzar la app empaquetada (hace falta el bundle para el esquema lifeos://).
if [ ! -d "$APP_PATH" ]; then
  echo "Empaquetando la app..."
  (cd "$PROJECT_ROOT" && ./scripts/build_dmg.sh > /dev/null)
fi

pkill -f "LIFEOS.app/Contents/MacOS/LIFEOS" 2>/dev/null || true
open -a "$APP_PATH" --args "${@:2}"
echo "LIFEOS lanzada contra el servidor local."
