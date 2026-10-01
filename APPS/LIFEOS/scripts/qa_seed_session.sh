#!/bin/sh
# QA: guarda en el llavero una sesión del servidor **local** de LifeOS, para
# poder revisar la app sin escribir credenciales a mano cada vez.
#
#   ./scripts/qa_seed_session.sh [http://127.0.0.1:8000]
#
# Rechaza a propósito cualquier servidor que no sea local: esto es una ayuda de
# desarrollo, no una forma de meter sesiones ajenas en el llavero.
#
# Nota: el ítem lo crea este script, no la app, así que la primera lectura puede
# tardar unos segundos mientras macOS comprueba el permiso. Para dejar el Mac
# limpio: `security delete-generic-password -s com.dmx83.lifeos -a session-token`.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BASE_URL="${1:-http://127.0.0.1:8000}"
USERNAME="${LIFEOS_QA_USER:-owner}"
PASSWORD="${LIFEOS_QA_PASSWORD:-change-me-in-dev}"

case "$BASE_URL" in
  http://127.0.0.1*|http://localhost*|http://192.168.*) ;;
  *)
    echo "Sólo servidores locales. Recibido: $BASE_URL"
    exit 1
    ;;
esac

TOKEN=$(curl -s --max-time 5 -X POST -H 'Content-Type: application/json' \
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}" \
  "$BASE_URL/api/v1/auth/native/login" \
  | "$(command -v python3)" -c 'import json,sys; print(json.load(sys.stdin)["token"])')

if [ -z "$TOKEN" ]; then
  echo "No se pudo obtener la sesión de $BASE_URL"
  exit 1
fi

security delete-generic-password -s com.dmx83.lifeos -a session-token > /dev/null 2>&1 || true
APP_PATH="$PROJECT_ROOT/build/Build/Products/Release/LIFEOS.app"
if [ -d "$APP_PATH" ]; then
  security add-generic-password -s com.dmx83.lifeos -a session-token -w "$TOKEN" -U -T "$APP_PATH" > /dev/null
else
  security add-generic-password -s com.dmx83.lifeos -a session-token -w "$TOKEN" -U > /dev/null
fi

echo "Sesión guardada para $USERNAME en $BASE_URL"
