#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/app_env.sh"

cd "$REPO_ROOT"

APP_NAME="JUST4ALL"
DERIVED_DIR="build"
DIST_DIR="dist"
BUNDLE_ID="com.dmx83.just4all"
DOWNLOADS_DIR="Sources/JUST4ALL/Resources/Downloads"

xcodebuild -scheme "$APP_NAME" -configuration Release -destination 'platform=macOS' -derivedDataPath "$DERIVED_DIR" \
  INFOPLIST_FILE="$REPO_ROOT/Sources/JUST4ALL/Resources/Info.plist"

APP_PATH=$(find "$DERIVED_DIR" -name "$APP_NAME.app" -type d | head -n 1)
if [ -z "$APP_PATH" ]; then
  APP_BIN="$DERIVED_DIR/Build/Products/Release/$APP_NAME"
  APP_PATH="$DERIVED_DIR/Build/Products/Release/$APP_NAME.app"

  if [ ! -f "$APP_BIN" ]; then
    echo "App executable not found."
    exit 1
  fi

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
  <key>CFBundleIconFile</key>
  <string>icon.icns</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_MACOS_VERSION</string>
</dict>
</plist>
EOF

  if [ -d "Sources/JUST4ALL/Resources" ]; then
    cp -R "Sources/JUST4ALL/Resources"/* "$APP_PATH/Contents/Resources/"
  fi

  if [ -f "Sources/JUST4ALL/Resources/Assets/JUST4ALL/icon.icns" ]; then
    cp "Sources/JUST4ALL/Resources/Assets/JUST4ALL/icon.icns" "$APP_PATH/Contents/Resources/icon.icns"
  fi
fi

if [ -d "Sources/JUST4ALL/Resources/Downloads" ]; then
  mkdir -p "$APP_PATH/Contents/Resources/Downloads"
  cp -R "Sources/JUST4ALL/Resources/Downloads"/* "$APP_PATH/Contents/Resources/Downloads/"
fi

if [ ! -d "$DOWNLOADS_DIR" ]; then
  echo "Downloads folder missing: $DOWNLOADS_DIR"
  exit 1
fi

for dmg in JUST4PDF.dmg JUST4CONVERT.dmg; do
  if [ ! -f "$DOWNLOADS_DIR/$dmg" ]; then
    echo "Missing DMG: $DOWNLOADS_DIR/$dmg"
    exit 1
  fi
done

mkdir -p "$DIST_DIR"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"

hdiutil create -volname "$APP_NAME" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH"

echo "DMG creado en $DMG_PATH"
