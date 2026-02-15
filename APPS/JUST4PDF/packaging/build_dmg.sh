#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PROJECT_ROOT/../.." && pwd)"

. "$REPO_ROOT/scripts/app_env.sh"

export APP_VERSION
export MIN_MACOS_VERSION

cd "$PROJECT_ROOT"

sh "$SCRIPT_DIR/build.sh"

APP_PATH="$PROJECT_ROOT/dist/JUST4PDF.app"
if [ ! -d "$APP_PATH" ]; then
  echo "JUST4PDF.app not found at $APP_PATH"
  exit 1
fi

DIST_DIR="$PROJECT_ROOT/dist"
DMG_PATH="$DIST_DIR/JUST4PDF.dmg"

hdiutil create -volname "JUST4PDF" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH"

echo "DMG creado en $DMG_PATH"

