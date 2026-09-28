#!/bin/sh
set -e

# Smoke test de release — JUST4PICT
# Uso: ./scripts/smoke_release.sh [--no-dmg]
#
#   1) swift test (suite completa: pipeline, formatos, historial, regresión visual)
#   2) swift build -c release (validación del binario)
#   3) build DMG (./scripts/build_dmg.sh)              [omitible con --no-dmg]
#   4) validación de build stamp en Info.plist y artefacto en dist/
#
# Deja un reporte consolidado por corrida en build/smoke-release-<stamp>.txt

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PROJECT_ROOT/../.." && pwd)"

WITH_DMG=1
if [ "$1" = "--no-dmg" ]; then
  WITH_DMG=0
fi

APP_ENV_SCRIPT_DIR="$REPO_ROOT/scripts"
. "$REPO_ROOT/scripts/app_env.sh"

cd "$PROJECT_ROOT"

REPORT_DIR="$PROJECT_ROOT/build"
mkdir -p "$REPORT_DIR"
REPORT="$REPORT_DIR/smoke-release-$(date -u +%Y%m%d%H%M%S).txt"
MARKER="$REPORT_DIR/.smoke-start.marker"
touch "$MARKER"
START_TS=$(date +%s)

log() {
  echo "$1"
  echo "$1" >> "$REPORT"
}

log "SMOKE RELEASE — JUST4PICT"
log "version=$APP_VERSION · build=$APP_BUILD_VERSION · stamp esperado=$APP_BUILD_STAMP"
log ""

# 1) Suite completa
log "[1/4] swift test (suite completa)…"
TESTS_OUT="$REPORT_DIR/.smoke-tests.log"
if swift test > "$TESTS_OUT" 2>&1; then
  SUMMARY=$(grep -E "Executed [0-9]+ tests" "$TESTS_OUT" | tail -1 | sed 's/^ *//')
  log "      OK — $SUMMARY"
else
  log "      FALLO — últimas líneas:"
  tail -5 "$TESTS_OUT" >> "$REPORT"
  tail -5 "$TESTS_OUT"
  exit 1
fi
if grep -q "' failed" "$TESTS_OUT"; then
  log "      FALLO — hay tests con error (ver $TESTS_OUT)"
  exit 1
fi

# 2) Binario release
log "[2/4] swift build -c release…"
swift build -c release > /dev/null
BIN=".build/release/JUST4PICT"
if [ ! -x "$BIN" ]; then
  log "      FALLO — binario release no encontrado en $BIN"
  exit 1
fi
log "      OK — $BIN ($(du -h "$BIN" | cut -f1))"

# 3) DMG
if [ "$WITH_DMG" -eq 1 ]; then
  log "[3/4] build DMG (xcodebuild + hdiutil)…"
  if sh "$SCRIPT_DIR/build_dmg.sh" > "$REPORT_DIR/.smoke-dmg.log" 2>&1; then
    log "      OK — DMG generado"
  else
    log "      FALLO — últimas líneas de $REPORT_DIR/.smoke-dmg.log:"
    tail -5 "$REPORT_DIR/.smoke-dmg.log" >> "$REPORT"
    tail -5 "$REPORT_DIR/.smoke-dmg.log"
    exit 1
  fi
else
  log "[3/4] DMG omitido (--no-dmg)"
fi

# 4) Validación de artefacto + build stamp
log "[4/4] validación de build stamp…"
if [ "$WITH_DMG" -eq 0 ]; then
  echo "$APP_BUILD_STAMP" | grep -Eq '^[0-9]{14}-[0-9a-f]+$' || {
    log "      FALLO — formato de build stamp inesperado: '$APP_BUILD_STAMP'"
    exit 1
  }
  log "      OK (--no-dmg) — stamp con formato válido: $APP_BUILD_STAMP"
else
  # El .app puede venir de un build anterior; validamos frescura por el Info.plist
  # (build_dmg lo reescribe en cada corrida) y no por la fecha del directorio.
  PLIST_NEW=$(find "$PROJECT_ROOT/build" -maxdepth 7 -path "*JUST4PICT.app/Contents/Info.plist" -newer "$MARKER" 2> /dev/null | head -n 1)
  if [ -z "$PLIST_NEW" ]; then
    log "      FALLO — build_dmg no actualizó un JUST4PICT.app en esta corrida"
    exit 1
  fi
  APP_PATH="${PLIST_NEW%/Contents/Info.plist}"

  STAMP=$(/usr/libexec/PlistBuddy -c "Print :J4ABuildStamp" "$APP_PATH/Contents/Info.plist" 2> /dev/null || echo "")
  PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2> /dev/null || echo "")
  echo "$STAMP" | grep -Eq '^[0-9]{14}-[0-9a-f]+$' || {
    log "      FALLO — formato de build stamp inesperado: '$STAMP'"
    exit 1
  }
  [ "$PLIST_VERSION" = "$APP_VERSION" ] || {
    log "      FALLO — versión del Info.plist ($PLIST_VERSION) != versión esperada ($APP_VERSION)"
    exit 1
  }
  STAMP_SHA="${STAMP##*-}"
  EXPECTED_SHA="${APP_BUILD_STAMP##*-}"
  [ "$STAMP_SHA" = "$EXPECTED_SHA" ] || {
    log "      FALLO — commit del build stamp ($STAMP_SHA) != HEAD ($EXPECTED_SHA)"
    exit 1
  }
  log "      OK — J4ABuildStamp=$STAMP (mismo commit, formato y versión válidos)"

  LATEST="$PROJECT_ROOT/dist/JUST4PICT-latest.dmg"
  if [ -e "$LATEST" ]; then
    TARGET=$(readlink "$LATEST" 2> /dev/null || basename "$LATEST")
    log "      OK — artefacto: dist/$TARGET"
  else
    log "      FALLO — no existe dist/JUST4PICT-latest.dmg"
    exit 1
  fi
fi

END_TS=$(date +%s)
log ""
log "RESULTADO: OK en $((END_TS - START_TS)) s · reporte: $REPORT"
echo "Smoke release OK."
