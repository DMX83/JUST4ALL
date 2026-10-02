#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSETS_DIR="$REPO_ROOT/dist/release-assets"

SUITE_VERSION="$(awk '/MARKETING_VERSION:/{print $2; exit}' "$REPO_ROOT/project.yml")"
if [ -z "$SUITE_VERSION" ]; then
  echo "Could not read MARKETING_VERSION from project.yml"
  exit 1
fi

# Versión de una subapp: la suya si declara APPS/<app>/VERSION, si no la del hub.
app_version() {
  APP_DIR="$REPO_ROOT/APPS/$1"
  if [ -f "$APP_DIR/VERSION" ]; then
    tr -d '[:space:]' < "$APP_DIR/VERSION"
  else
    printf '%s' "$SUITE_VERSION"
  fi
}

# El nombre del asset lleva la versión REAL de cada app: el hub la compara con la
# instalada para ofrecer «Actualizar», así que no puede ser la del hub para todas.
copy_dmg() {
  SLUG="$1"
  SOURCE_PATH="$REPO_ROOT/APPS/$SLUG/dist/$SLUG.dmg"
  DEST_NAME="$SLUG-$(app_version "$SLUG").dmg"

  if [ ! -f "$SOURCE_PATH" ]; then
    echo "Missing DMG: $SOURCE_PATH"
    echo "  -> constrúyelo con APPS/$SLUG/scripts/build_dmg.sh"
    exit 1
  fi

  mkdir -p "$ASSETS_DIR"
  cp -f "$SOURCE_PATH" "$ASSETS_DIR/$DEST_NAME"

  # Un solo asset por subapp: si quedaba otro de una versión distinta, fuera.
  for OLD in "$ASSETS_DIR/$SLUG-"*.dmg; do
    [ -f "$OLD" ] || continue
    [ "$(basename "$OLD")" = "$DEST_NAME" ] || rm -f "$OLD"
  done

  echo "  OK  $DEST_NAME"
}

copy_dmg JUST4PDF
copy_dmg JUST4CONVERT
copy_dmg JUST4PICT
copy_dmg JUST4FOLDERS
copy_dmg JUST4DESK
copy_dmg LIFEOS

# SHA256SUMS.txt: sin él el hub se niega a descargar (verifica el hash antes de abrir).
rm -f "$ASSETS_DIR/SHA256SUMS.txt"
( cd "$ASSETS_DIR" && shasum -a 256 ./*.dmg > SHA256SUMS.txt )

printf "Prepared release assets in %s\n" "$ASSETS_DIR"
cat "$ASSETS_DIR/SHA256SUMS.txt"
