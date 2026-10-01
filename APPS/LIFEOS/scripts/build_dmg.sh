#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PROJECT_ROOT/../.." && pwd)"

APP_ENV_SCRIPT_DIR="$REPO_ROOT/scripts"
. "$REPO_ROOT/scripts/app_env.sh"

cd "$PROJECT_ROOT"

APP_NAME="LIFEOS"
DERIVED_DIR="build"
DIST_DIR="dist"
BUNDLE_ID="com.dmx83.lifeos"
APP_LABEL="$APP_NAME-$APP_VERSION+$APP_BUILD_STAMP"

# 1) Compilación Release (SwiftPM: no hay .xcodeproj propio, como en el resto de subapps).
swift build -c release --product "$APP_NAME" --scratch-path "$DERIVED_DIR"

APP_BIN="$DERIVED_DIR/release/$APP_NAME"
if [ ! -f "$APP_BIN" ]; then
  # Por si el toolchain decide usar otra carpeta de arquitectura.
  APP_BIN=$(find "$DERIVED_DIR" -type f -name "$APP_NAME" -perm +111 | head -n 1)
fi
if [ ! -f "$APP_BIN" ]; then
  echo "No se encontró el ejecutable de $APP_NAME."
  exit 1
fi

# 2) Bundle .app con su Info.plist.
APP_PATH="$DERIVED_DIR/Build/Products/Release/$APP_NAME.app"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$APP_BIN" "$APP_PATH/Contents/MacOS/$APP_NAME"

# CFBundleURLTypes es imprescindible: el acceso con Google vuelve a la app con
# el esquema lifeos://, y sin declararlo macOS no sabe a quién entregar la URL.
cat > "$APP_PATH/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>LifeOS</string>
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
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>NSHumanReadableCopyright</key>
  <string>LifeOS — JUST4ALL</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>LifeOS graba notas de voz para guardarlas y transcribirlas en tu servidor de LifeOS.</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>$BUNDLE_ID</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>lifeos</string>
      </array>
    </dict>
  </array>
  <!-- Tipos que la app puede abrir («Abrir con LifeOS» y doble clic). Son los
       mismos cuatro que acepta POST /documents/upload: si aquí se anunciara
       alguno más, macOS ofrecería LifeOS para ficheros que luego rechaza. -->
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>
      <string>Documento para LifeOS</string>
      <key>CFBundleTypeRole</key>
      <string>Editor</string>
      <key>LSHandlerRank</key>
      <string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>com.adobe.pdf</string>
        <string>org.openxmlformats.wordprocessingml.document</string>
        <string>public.plain-text</string>
        <string>net.daringfireball.markdown</string>
      </array>
    </dict>
  </array>
  <!-- Menú Servicios: «Capturar en LifeOS» con lo seleccionado. El NSMessage
       apunta a AppDelegate.sendSelection(_:userData:error:). -->
  <key>NSServices</key>
  <array>
    <dict>
      <key>NSMenuItem</key>
      <dict>
        <key>default</key>
        <string>Capturar en LifeOS</string>
      </dict>
      <key>NSMessage</key>
      <string>sendSelection</string>
      <key>NSPortName</key>
      <string>$APP_NAME</string>
      <key>NSSendTypes</key>
      <array>
        <string>NSStringPboardType</string>
        <string>NSRTFPboardType</string>
        <string>NSFilenamesPboardType</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
EOF

if [ -f "packaging/macos/AppIcon.icns" ]; then
  cp "packaging/macos/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon.icns" "$APP_PATH/Contents/Info.plist"
else
  echo "Aviso: packaging/macos/AppIcon.icns no encontrado; el bundle irá sin icono propio."
fi

# 2.5) Firma con la identidad de desarrollo, si la hay.
#
# Y esto importa más de lo que parece: **el llavero**. Con firma ad-hoc, cada
# compilación produce un cdhash distinto, así que macOS considera que es «otra
# app» y vuelve a pedir permiso para leer la sesión guardada cada vez que se
# recompila. Firmando con una identidad de desarrollo la ACL del elemento se
# satisface por identidad (equipo + identificador) y el aviso deja de salir.
#
# Se puede forzar otra identidad: CODESIGN_IDENTITY="Developer ID Application: …"
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' | head -n 1)}"

if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" --timestamp=none --identifier "$BUNDLE_ID" "$APP_PATH"
  codesign --verify --strict "$APP_PATH"
  echo "Firmada con: $IDENTITY"
else
  echo "Aviso: no hay identidad de desarrollo en el llavero; la app queda ad-hoc."
  echo "        El llavero volverá a pedir permiso en cada compilación (CODESIGN_IDENTITY permite indicar otra)."
fi

# 3) DMG.
mkdir -p "$DIST_DIR"
DMG_PATH="$DIST_DIR/$APP_LABEL.dmg"
STAGING_DIR="$DIST_DIR/staging-$APP_NAME"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create -volname "LifeOS" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"
rm -rf "$STAGING_DIR"

ln -sf "$(basename "$DMG_PATH")" "$DIST_DIR/$APP_NAME.dmg"
ln -sf "$(basename "$DMG_PATH")" "$DIST_DIR/$APP_NAME-latest.dmg"

echo "DMG creado en $DMG_PATH"
