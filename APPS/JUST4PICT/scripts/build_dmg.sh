#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PROJECT_ROOT/../.." && pwd)"

APP_ENV_SCRIPT_DIR="$REPO_ROOT/scripts"
. "$REPO_ROOT/scripts/app_env.sh"

cd "$PROJECT_ROOT"

APP_NAME="JUST4PICT"
DERIVED_DIR="build"
DIST_DIR="dist"
BUNDLE_ID="com.dmx83.just4pict"
APP_LABEL="$APP_NAME-$APP_VERSION+$APP_BUILD_STAMP"

xcodebuild -scheme "$APP_NAME" -configuration Release -destination 'platform=macOS' -derivedDataPath "$DERIVED_DIR"

# xcodebuild construye el paquete SwiftPM: deja el BINARIO, no el .app, así que el bundle
# se rehace siempre desde lo recién compilado. Antes esto colgaba de un `find`: si quedaba
# un .app de una compilación anterior, se empaquetaba ése y sólo se le cambiaba el sello
# (un DMG que decía «hoy» llevando código de semanas antes).
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

cat > "$APP_PATH/Contents/Info.plist" <<EOF
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
  <string>$APP_BUILD_VERSION</string>
  <key>J4ABuildStamp</key>
  <string>$APP_BUILD_STAMP</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_MACOS_VERSION</string>
</dict>
</plist>
EOF

INFO_PLIST="$APP_PATH/Contents/Info.plist"
if [ -f "$INFO_PLIST" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$INFO_PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $APP_VERSION" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_BUILD_VERSION" "$INFO_PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $APP_BUILD_VERSION" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Set :J4ABuildStamp $APP_BUILD_STAMP" "$INFO_PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :J4ABuildStamp string $APP_BUILD_STAMP" "$INFO_PLIST"
fi

mkdir -p "$DIST_DIR"
DMG_PATH="$DIST_DIR/$APP_LABEL.dmg"

hdiutil create -volname "$APP_NAME" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH"

ln -sf "$(basename "$DMG_PATH")" "$DIST_DIR/$APP_NAME.dmg"
ln -sf "$(basename "$DMG_PATH")" "$DIST_DIR/$APP_NAME-latest.dmg"

echo "DMG creado en $DMG_PATH"
