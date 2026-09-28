#!/bin/zsh
# Instala el Quick Action «Enviar a JUST4DESK» en ~/Library/Services.
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
WF="Enviar a JUST4DESK.workflow"
DEST="$HOME/Library/Services"

if [ ! -d "$DIR/$WF" ]; then
  echo "No encuentro «$WF» junto a este instalador."
  exit 1
fi

mkdir -p "$DEST"
rm -rf "$DEST/$WF"
cp -R "$DIR/$WF" "$DEST/"

# Refresca el registro de servicios (pbs es opcional en macOS moderno).
/System/Library/CoreServices/pbs -flush 2>/dev/null || true

echo "✔ Instalado en $DEST/$WF"
echo "  Aparecerá en Finder → clic derecho → Servicios (puede tardar unos segundos)."
echo ""
read -r "?Pulsa Intro para cerrar…" dummy_variable
