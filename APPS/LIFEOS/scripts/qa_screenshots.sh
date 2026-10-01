#!/bin/sh
# Captura las ventanas de LIFEOS en claro y en oscuro, para la revisión visual.
#
#   ./scripts/qa_screenshots.sh [carpeta_de_salida]
#
# OJO: esta vía depende del escritorio y en la práctica es frágil — `screencapture`
# devuelve imágenes negras si la pantalla está dormida, y capturar por ventana
# (`-l`) o por rectángulo (`-R`) puede estar bloqueado por el sistema. La vía
# fiable es renderizar las vistas fuera de pantalla:
#
#   LIFEOS_RENDER_PREVIEWS=1 swift test --filter RenderPreviewsTests
#
# Se conserva porque, con la pantalla despierta y el permiso concedido, da la
# ventana real (barra lateral nativa incluida).
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PROJECT_ROOT/../.." && pwd)"
OUT="${1:-$PROJECT_ROOT/docs/design/v2-apple}"
APP="$PROJECT_ROOT/build/Build/Products/Release/LIFEOS.app"

LOGICAL_W=${LOGICAL_W:-1728}
if [ ! -d "$APP" ]; then
  echo "Falta $APP: ejecuta antes ./scripts/build_dmg.sh"
  exit 1
fi

mkdir -p "$OUT"

# La pantalla tiene que estar despierta: con el display dormido `screencapture`
# devuelve una imagen negra (y a veces falla directamente). Misma lección que en
# la QA visual de JUST4DESK.
caffeinate -u -t 600 &
CAFFEINATE_PID=$!
trap 'kill "$CAFFEINATE_PID" 2>/dev/null || true' EXIT

stop_app() {
  pkill -f "LIFEOS.app/Contents/MacOS/LIFEOS" 2>/dev/null || true
  sleep 1
}

# Rectángulo de la ventana más ancha (la principal) y del panel flotante.
main_rect() {
  "$WINDOWS" | head -1 | awk -F'\t' '{ print $2","$3","$4","$5 }'
}

panel_rect() {
  "$WINDOWS" | awk -F'\t' '$4 < 900 { print $2","$3","$4","$5; exit }'
}

PYTHON="$REPO_ROOT/.venv/bin/python"
[ -x "$PYTHON" ] || PYTHON="$(command -v python3)"

FULL="${TMPDIR:-/tmp}/lifeos-qa-full.png"
WINDOWS="${TMPDIR:-/tmp}/lifeos-qa-windows"

# El ayudante se compila UNA vez: `swift script.swift` recompila en cada llamada
# y con ~20 llamadas el proceso se va a minutos (y la pantalla se duerme).
if [ ! -x "$WINDOWS" ] || [ "$SCRIPT_DIR/window_id.swift" -nt "$WINDOWS" ]; then
  swiftc -O "$SCRIPT_DIR/window_id.swift" -o "$WINDOWS"
fi

LOGICAL_W=$("$WINDOWS" --screen | cut -f1)
LOGICAL_W=${LOGICAL_W:-1728}

# Captura toda la pantalla y recorta la ventana indicada, comprobando que la
# imagen no salga negra (síntoma de pantalla dormida o de permiso de grabación).
shoot() {
  rect="$1"
  target="$2"
  [ -n "$rect" ] || { echo "    (sin ventana para $(basename "$target"))"; return 0; }

  screencapture -x "$FULL" 2>/dev/null || { echo "    (falló la captura de pantalla)"; return 0; }

  "$PYTHON" - "$FULL" "$rect" "$LOGICAL_W" "$target" <<'PY'
import sys
from PIL import Image

full_path, rect, logical_width, target = sys.argv[1:5]
x, y, w, h = (int(value) for value in rect.split(","))
image = Image.open(full_path)
scale = image.size[0] / float(logical_width)
box = (int(x * scale), int(y * scale), int((x + w) * scale), int((y + h) * scale))
crop = image.crop(box)
crop.save(target)

# Una imagen de un solo color significa que la captura no sirvió.
if len(crop.convert("RGB").getcolors(maxcolors=4) or []) <= 2:
    print("UNIFORME")
PY

  echo "    $(basename "$target")"
}

activate() {
  osascript -e 'tell application "LIFEOS" to activate' > /dev/null 2>&1 || true
  sleep 1
}

for theme in light dark; do
  echo "Tema $theme"
  for pane in today capture inbox settings; do
    defaults write com.dmx83.lifeos lifeos.lastPane "$pane"
    stop_app
    open -a "$APP" --args --appearance "$theme"
    sleep 5
    activate
    shoot "$(main_rect)" "$OUT/$theme-$pane.png"
  done

  # Panel de captura rápida (⌥Espacio).
  stop_app
  open -a "$APP" --args --appearance "$theme" --quick-capture
  sleep 5
  activate
  shoot "$(panel_rect)" "$OUT/$theme-panel.png"
done

stop_app
echo "Capturas en $OUT"
