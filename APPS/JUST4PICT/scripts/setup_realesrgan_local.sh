#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE_DIR="$APP_ROOT/.cache/realesrgan"
RELEASE_VERSION="v0.2.0"
ARCHIVE_NAME="realesrgan-ncnn-vulkan-v0.2.0-macos.zip"
ARCHIVE_URL="https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan/releases/download/${RELEASE_VERSION}/${ARCHIVE_NAME}"
EXTRACTED_DIR="$CACHE_DIR/realesrgan-ncnn-vulkan-v0.2.0-macos"
MODELS_DIR="$CACHE_DIR/models"

mkdir -p "$CACHE_DIR"
mkdir -p "$MODELS_DIR"

echo "Downloading Real-ESRGAN ncnn Vulkan ${RELEASE_VERSION}..."
curl -fsSL -o "$CACHE_DIR/$ARCHIVE_NAME" "$ARCHIVE_URL"

echo "Extracting archive..."
rm -rf "$EXTRACTED_DIR"
unzip -o "$CACHE_DIR/$ARCHIVE_NAME" -d "$CACHE_DIR" >/dev/null

BIN_PATH="$EXTRACTED_DIR/realesrgan-ncnn-vulkan"

if [[ ! -x "$BIN_PATH" ]]; then
  echo "Binary not found after extraction: $BIN_PATH" >&2
  exit 1
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
  The official macOS zip provides the executable, but not always the model files.
  JUST4PICT will keep falling back to local Lanczos until both model files are present.

EOF
