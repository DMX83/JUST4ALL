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

copy_dmg() {
  SOURCE_PATH="$1"
  DEST_NAME="$2"

  if [ ! -f "$SOURCE_PATH" ]; then
    echo "Missing DMG: $SOURCE_PATH"
    exit 1
  fi

  mkdir -p "$ASSETS_DIR"
  cp -f "$SOURCE_PATH" "$ASSETS_DIR/$DEST_NAME"
}

copy_dmg "$REPO_ROOT/APPS/JUST4PDF/dist/JUST4PDF.dmg" "JUST4PDF-$SUITE_VERSION.dmg"
copy_dmg "$REPO_ROOT/APPS/JUST4CONVERT/dist/JUST4CONVERT.dmg" "JUST4CONVERT-$SUITE_VERSION.dmg"

printf "Prepared release assets in %s\n" "$ASSETS_DIR"
