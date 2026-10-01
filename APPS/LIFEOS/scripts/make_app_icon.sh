#!/bin/sh
# Construye el icono del bundle (packaging/macos/AppIcon.icns) a partir de la
# marca, para que LIFEOS.app no salga con el icono genérico en el Dock.
#
#   ./scripts/make_app_icon.sh
#
# Necesita Pillow: usa el .venv del repo JUST4ALL (que ya lo tiene).
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PROJECT_ROOT/../.." && pwd)"

PYTHON="$REPO_ROOT/.venv/bin/python"
if [ ! -x "$PYTHON" ]; then
  PYTHON="$(command -v python3)"
fi

ICONSET="$PROJECT_ROOT/packaging/macos/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# Nombres que exige `iconutil`: cada tamaño en 1x y 2x.
render() {
  "$PYTHON" "$SCRIPT_DIR/make_logo.py" "$ICONSET/$1" "$2" > /dev/null
}

render "icon_16x16.png" 16
render "icon_16x16@2x.png" 32
render "icon_32x32.png" 32
render "icon_32x32@2x.png" 64
render "icon_128x128.png" 128
render "icon_128x128@2x.png" 256
render "icon_256x256.png" 256
render "icon_256x256@2x.png" 512
render "icon_512x512.png" 512
render "icon_512x512@2x.png" 1024

iconutil -c icns "$ICONSET" -o "$PROJECT_ROOT/packaging/macos/AppIcon.icns"
rm -rf "$ICONSET"

echo "Icono creado: packaging/macos/AppIcon.icns"
