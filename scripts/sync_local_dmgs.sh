#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOWNLOADS_DIR="$REPO_ROOT/Sources/JUST4ALL/Resources/Downloads"

copy_dmg() {
  SOURCE_PATH="$1"
  DEST_NAME="$2"

  if [ ! -f "$SOURCE_PATH" ]; then
    echo "Missing DMG: $SOURCE_PATH"
    exit 1
  fi

  mkdir -p "$DOWNLOADS_DIR"
  cp -f "$SOURCE_PATH" "$DOWNLOADS_DIR/$DEST_NAME"
}

copy_dmg "$REPO_ROOT/APPS/JUST4PDF/dist/JUST4PDF.dmg" "JUST4PDF.dmg"
copy_dmg "$REPO_ROOT/APPS/JUST4CONVERT/dist/JUST4CONVERT.dmg" "JUST4CONVERT.dmg"

printf "Synced DMGs to %s\n" "$DOWNLOADS_DIR"
