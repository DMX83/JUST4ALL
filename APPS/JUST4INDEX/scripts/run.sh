#!/bin/zsh
# Lanza JUST4INDEX (modo desarrollo) desacoplado de la terminal.
# Uso: ./scripts/run.sh   (desde APPS/JUST4INDEX)
#      o la ruta completa: /Users/dmx83/Repos/JUST4ALL/APPS/JUST4INDEX/scripts/run.sh
set -e
cd "$(dirname "$0")/.."

BIN=".build/out/Products/Debug/JUST4INDEX"
if [ ! -x "$BIN" ]; then
  echo "Compilando JUST4INDEX…"
  swift build
fi

pkill -x JUST4INDEX 2>/dev/null || true
nohup "$BIN" >/tmp/j4i-app-stdio.log 2>&1 &!
echo "JUST4INDEX lanzado (pid $!). Registro: ~/Library/Logs/JUST4INDEX/just4index.log"
