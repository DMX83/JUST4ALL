#!/bin/zsh
# Lanza JUST4DESK (modo desarrollo) desacoplado de la terminal.
# Uso: ./scripts/run.sh   (desde APPS/JUST4DESK)
#      o la ruta completa: /Users/dmx83/Repos/JUST4ALL/APPS/JUST4DESK/scripts/run.sh
set -e
cd "$(dirname "$0")/.."

BIN=".build/out/Products/Debug/JUST4DESK"
if [ ! -x "$BIN" ]; then
  echo "Compilando JUST4DESK…"
  swift build
fi

pkill -x JUST4DESK 2>/dev/null || true
nohup "$BIN" >/tmp/j4i-app-stdio.log 2>&1 &!
echo "JUST4DESK lanzado (pid $!). Registro: ~/Library/Logs/JUST4DESK/just4desk.log"
