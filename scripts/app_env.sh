#!/bin/sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_VERSION="$(awk '/MARKETING_VERSION:/{print $2; exit}' "$REPO_ROOT/project.yml")"
if [ -z "$APP_VERSION" ]; then
  APP_VERSION="0.0.0"
fi

MIN_MACOS_VERSION="$(awk '/macOS:/{gsub(/\"/,\"\",$2); print $2; exit}' "$REPO_ROOT/project.yml")"
if [ -z "$MIN_MACOS_VERSION" ]; then
  MIN_MACOS_VERSION="13.0"
fi
