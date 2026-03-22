#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE_DIR="$APP_ROOT/.cache/realesrgan"
RELEASE_VERSION="v0.2.5.0"
ARCHIVE_NAME="realesrgan-ncnn-vulkan-20220424-macos.zip"
ARCHIVE_URL="https://github.com/xinntao/Real-ESRGAN/releases/download/${RELEASE_VERSION}/${ARCHIVE_NAME}"
EXTRACTED_DIR="$CACHE_DIR/realesrgan-ncnn-vulkan-20220424-macos"
MODELS_DIR="$CACHE_DIR/models"

mkdir -p "$CACHE_DIR"
mkdir -p "$MODELS_DIR"

echo "Downloading Real-ESRGAN ncnn Vulkan ${RELEASE_VERSION}..."
curl -fsSL -o "$CACHE_DIR/$ARCHIVE_NAME" "$ARCHIVE_URL"

echo "Extracting archive..."
rm -rf "$EXTRACTED_DIR"
mkdir -p "$EXTRACTED_DIR"
unzip -o "$CACHE_DIR/$ARCHIVE_NAME" -d "$EXTRACTED_DIR" >/dev/null

BIN_PATH="$EXTRACTED_DIR/realesrgan-ncnn-vulkan"
chmod +x "$BIN_PATH" 2>/dev/null || true

if [[ ! -x "$BIN_PATH" ]]; then
  echo "Binary not found after extraction: $BIN_PATH" >&2
  exit 1
fi

if [[ -f "$EXTRACTED_DIR/models/realesrgan-x4plus.param" && -f "$EXTRACTED_DIR/models/realesrgan-x4plus.bin" ]]; then
  cp -f "$EXTRACTED_DIR/models/realesrgan-x4plus.param" "$MODELS_DIR/"
  cp -f "$EXTRACTED_DIR/models/realesrgan-x4plus.bin" "$MODELS_DIR/"
fi

cat <<EOF

Real-ESRGAN local setup completed.

Binary:
  $BIN_PATH

Models directory:
  $MODELS_DIR

Required model files:
  $MODELS_DIR/realesrgan-x4plus.param
  $MODELS_DIR/realesrgan-x4plus.bin

Suggested shell exports:
  export JUST4PICT_REAL_ESRGAN_BIN="$BIN_PATH"
  export JUST4PICT_REAL_ESRGAN_MODELS="$MODELS_DIR"

Diagnostic command:
  JUST4PICT_RUN_UPSCALE_DIAGNOSTICS=1 swift test --filter ImageEnhancerDiagnosticsTests/testUpscaleDiagnosticComparesLocalAgainstRealESRGANOnLowResSample

Note:
  This official macOS asset includes the standard realesrgan-x4plus NCNN models.
  JUST4PICT will keep falling back to local Lanczos if those files are later removed.

EOF
