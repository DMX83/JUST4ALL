#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "QA repo samples — JUST4PICT"
echo "Usando muestras del repo en:"
echo "  $PROJECT_ROOT/images"
echo ""

swift test \
  --package-path "$PROJECT_ROOT" \
  --filter ImageEnhancerDiagnosticsTests/testWritesRepoSampleOutputsForQuickQA

echo ""
echo "Salidas esperadas:"
echo "  $PROJECT_ROOT/images/test/*-pro-sample.png"
