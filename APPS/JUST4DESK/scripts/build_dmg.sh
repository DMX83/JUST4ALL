#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PROJECT_ROOT/../.." && pwd)"

APP_ENV_SCRIPT_DIR="$REPO_ROOT/scripts"
. "$REPO_ROOT/scripts/app_env.sh"

cd "$PROJECT_ROOT"

APP_NAME="JUST4DESK"
DERIVED_DIR="build"
DIST_DIR="dist"
BUNDLE_ID="com.dmx83.just4desk"
ENTITLEMENTS="packaging/macos/JUST4DESK.entitlements"
APP_LABEL="$APP_NAME-$APP_VERSION+$APP_BUILD_STAMP"

xcodebuild -scheme "$APP_NAME" -configuration Release -destination 'platform=macOS' -derivedDataPath "$DERIVED_DIR" CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS"

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
  <key>NSDownloadsFolderUsageDescription</key>
  <string>JUST4DESK vigila tu carpeta de Descargas para clasificar y archivar los ficheros que lleguen.</string>
  <key>NSDesktopFolderUsageDescription</key>
  <string>JUST4DESK necesita leer las carpetas de entrada que elijas.</string>
  <key>NSDocumentsFolderUsageDescription</key>
  <string>JUST4DESK necesita leer las carpetas de entrada que elijas.</string>
  <key>NSRemovableVolumesUsageDescription</key>
  <string>JUST4DESK puede organizar documentos guardados en unidades externas.</string>
</dict>
</plist>
EOF
fi

INFO_PLIST="$APP_PATH/Contents/Info.plist"
if [ -f "$INFO_PLIST" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$INFO_PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $APP_VERSION" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_BUILD_VERSION" "$INFO_PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $APP_BUILD_VERSION" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Set :J4ABuildStamp $APP_BUILD_STAMP" "$INFO_PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :J4ABuildStamp string $APP_BUILD_STAMP" "$INFO_PLIST"
  # Descripciones de uso TCC: macOS las muestra en los avisos de permisos de carpetas.
  /usr/libexec/PlistBuddy -c "Add :NSDownloadsFolderUsageDescription string 'JUST4DESK vigila tu carpeta de Descargas para clasificar y archivar los ficheros que lleguen.'" "$INFO_PLIST" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :NSDesktopFolderUsageDescription string 'JUST4DESK necesita leer las carpetas de entrada que elijas.'" "$INFO_PLIST" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :NSDocumentsFolderUsageDescription string 'JUST4DESK necesita leer las carpetas de entrada que elijas.'" "$INFO_PLIST" 2>/dev/null || true

  # F15.x — icono propio: copia el .icns al bundle y lo declara en el Info.plist.
  if [ -f "packaging/macos/AppIcon.icns" ]; then
    mkdir -p "$APP_PATH/Contents/Resources"
    cp "packaging/macos/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon.icns" "$INFO_PLIST" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon.icns" "$INFO_PLIST"
  else
    echo "Aviso: packaging/macos/AppIcon.icns no encontrado; el bundle irá sin icono propio."
  fi
fi

mkdir -p "$DIST_DIR"
DMG_PATH="$DIST_DIR/$APP_LABEL.dmg"

# N6 — staging del DMG: app + Quick Action de Finder («Enviar a JUST4DESK») + LEEME.
STAGING_DIR="$DIST_DIR/staging-$APP_NAME"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
if [ -d "packaging/quick_action/Enviar a JUST4DESK.workflow" ]; then
  cp -R "packaging/quick_action/Enviar a JUST4DESK.workflow" "$STAGING_DIR/"
  cp "packaging/quick_action/LEEME.txt" "$STAGING_DIR/"
  [ -f "packaging/quick_action/Instalar Quick Action.command" ] && \
    cp "packaging/quick_action/Instalar Quick Action.command" "$STAGING_DIR/"
else
  echo "Aviso: Quick Action no encontrada; el DMG solo llevará la app."
fi

hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"
rm -rf "$STAGING_DIR"

ln -sf "$(basename "$DMG_PATH")" "$DIST_DIR/$APP_NAME.dmg"
ln -sf "$(basename "$DMG_PATH")" "$DIST_DIR/$APP_NAME-latest.dmg"

echo "DMG creado en $DMG_PATH"
