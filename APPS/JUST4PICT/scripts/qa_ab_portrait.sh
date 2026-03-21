#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "QA A/B Retrato JUST4PICT"
echo ""
echo "Modo PRO (default):"
echo "  JUST4PICT_PORTRAIT_PROFILE=pro swift run --package-path \"$PROJECT_ROOT\" JUST4PICT"
echo ""
echo "Modo LEGACY (comparativa):"
echo "  JUST4PICT_PORTRAIT_PROFILE=legacy swift run --package-path \"$PROJECT_ROOT\" JUST4PICT"
echo ""
echo "Tip: procesa la misma foto en ambos modos y compara resultado final."
