#!/bin/zsh
# JUST4INDEX — registro en vivo desde la terminal.
#
# Uso:
#   ./scripts/log_watch.sh          # sigue el registro unificado de macOS (subsystem com.dmx83.just4index)
#   ./scripts/log_watch.sh --file   # sigue el archivo ~/Library/Logs/JUST4INDEX/just4index.log
#
# Dentro de la app: menú «Carpetas» → «Ver registro…» (⌘L) muestra el mismo registro en vivo.
set -euo pipefail

LOG_FILE="$HOME/Library/Logs/JUST4INDEX/just4index.log"

if [[ "${1:-}" == "--file" ]]; then
    if [[ ! -f "$LOG_FILE" ]]; then
        echo "Todavía no existe $LOG_FILE (la app aún no ha escrito ninguna entrada)." >&2
        exit 0
    fi
    exec tail -n 200 -f "$LOG_FILE"
else
    echo "Siguiendo el registro unificado «com.dmx83.just4index» (Ctrl-C para salir)."
    echo "Archivo: $LOG_FILE · Visor en la app: Carpetas → Ver registro… (⌘L)"
    exec log stream --style compact --level debug --predicate 'subsystem == "com.dmx83.just4index"'
fi
