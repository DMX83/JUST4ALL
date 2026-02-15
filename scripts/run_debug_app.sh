#!/bin/sh
set -e

cd "$(dirname "$0")/.."

APP_NAME="JUST4ALL"
DERIVED_DIR="build"
BUNDLE_ID="com.dmx83.just4all"

. "$(dirname "$0")/app_env.sh"

xcodebuild -scheme "$APP_NAME" -configuration Debug -destination 'platform=macOS' -derivedDataPath "$DERIVED_DIR"

APP_PATH=$(find "$DERIVED_DIR" -name "$APP_NAME.app" -type d | head -n 1)
if [ -z "$APP_PATH" ]; then
  APP_BIN="$DERIVED_DIR/Build/Products/Debug/$APP_NAME"
  APP_PATH="$DERIVED_DIR/Build/Products/Debug/$APP_NAME.app"

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

open "$APP_PATH"
