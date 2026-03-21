#!/bin/sh

if [ -n "$APP_ENV_SCRIPT_DIR" ]; then
  APP_ENV_DIR="$APP_ENV_SCRIPT_DIR"
else
  APP_ENV_DIR="$(cd "$(dirname "$0")" && pwd)"
fi
REPO_ROOT="$(cd "$APP_ENV_DIR/.." && pwd)"

APP_VERSION="$(awk '/MARKETING_VERSION:/{print $2; exit}' "$REPO_ROOT/project.yml")"
if [ -z "$APP_VERSION" ]; then
  APP_VERSION="0.0.0"
fi

GIT_SHORT_SHA="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo nogit)"
BUILD_TIMESTAMP_UTC="$(date -u +%Y%m%d%H%M%S)"
APP_BUILD_STAMP="$BUILD_TIMESTAMP_UTC-$GIT_SHORT_SHA"
APP_BUILD_VERSION="$(awk '/CURRENT_PROJECT_VERSION:/{print $2; exit}' "$REPO_ROOT/project.yml")"
if [ -z "$APP_BUILD_VERSION" ]; then
  APP_BUILD_VERSION="$BUILD_TIMESTAMP_UTC"
fi

MIN_MACOS_VERSION="$(awk '/macOS:/{gsub(/"/,"",$2); print $2; exit}' "$REPO_ROOT/project.yml")"
if [ -z "$MIN_MACOS_VERSION" ]; then
  MIN_MACOS_VERSION="13.0"
fi
