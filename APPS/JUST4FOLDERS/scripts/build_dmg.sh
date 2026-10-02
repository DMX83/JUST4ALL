#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PROJECT_ROOT/../.." && pwd)"

APP_ENV_SCRIPT_DIR="$REPO_ROOT/scripts"
. "$REPO_ROOT/scripts/app_env.sh"

cd "$PROJECT_ROOT"

APP_NAME="JUST4FOLDERS"
DERIVED_DIR="build"
DIST_DIR="dist"
BUNDLE_ID="com.dmx83.just4folders"
ENTITLEMENTS_FILE="$PROJECT_ROOT/packaging/macos/JUST4FOLDERS.entitlements"

# La versión la manda APPS/JUST4FOLDERS/VERSION (vía app_env.sh): sin esto, xcodebuild
# graba en el bundle el MARKETING_VERSION del .xcodeproj y todos los DMG salen «0.1.0»,
# indistinguibles del de hace meses y sin forma de que el hub ofrezca «Actualizar».
xcodebuild -scheme "$APP_NAME" -configuration Release -destination 'platform=macOS' -derivedDataPath "$DERIVED_DIR" CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS_FILE" MARKETING_VERSION="$APP_VERSION" CURRENT_PROJECT_VERSION="$APP_BUILD_VERSION"

# xcodebuild construye el paquete SwiftPM y deja el BINARIO, no el .app. Antes esto se
# dejaba al azar de un `find`: si quedaba un .app de una compilación vieja, se
# empaquetaba ÉSE (de ahí un DMG de octubre con el código de marzo). Ahora el bundle
# se rehace siempre desde el binario recién compilado.
APP_BIN="$DERIVED_DIR/Build/Products/Release/$APP_NAME"
if [ ! -f "$APP_BIN" ]; then
  APP_BIN=".build/release/$APP_NAME"
fi
if [ ! -f "$APP_BIN" ]; then
  echo "App executable not found: ni $DERIVED_DIR/Build/Products/Release/$APP_NAME ni .build/release/$APP_NAME"
  exit 1
fi

APP_PATH="$DERIVED_DIR/Build/Products/Release/$APP_NAME.app"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$APP_BIN" "$APP_PATH/Contents/MacOS/$APP_NAME"

cat > "$APP_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_VERSION</string>
  <key>J4ABuildStamp</key>
  <string>$APP_BUILD_STAMP</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_MACOS_VERSION</string>
</dict>
</plist>
PLIST

mkdir -p "$DIST_DIR"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"

hdiutil create -volname "$APP_NAME" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH"

echo "DMG creado en $DMG_PATH"
