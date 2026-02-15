#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SUITE_VERSION="$(awk '/MARKETING_VERSION:/{print $2; exit}' "$REPO_ROOT/project.yml")"
if [ -z "$SUITE_VERSION" ]; then
  echo "Could not read MARKETING_VERSION from project.yml"
  exit 1
fi

update_toml_version() {
  FILE="$1"
  if [ ! -f "$FILE" ]; then
    return
  fi
  # Replace: version = "x.y.z"
  perl -0777 -i -pe "s/version\\s*=\\s*\\\"[0-9]+\\.[0-9]+\\.[0-9]+\\\"/version = \\\"$SUITE_VERSION\\\"/g" "$FILE"
}

update_cfg_version() {
  FILE="$1"
  if [ ! -f "$FILE" ]; then
    return
  fi
  # Replace: version = x.y.z
  perl -0777 -i -pe "s/^version\\s*=\\s*[0-9]+\\.[0-9]+\\.[0-9]+/version = $SUITE_VERSION/mg" "$FILE"
}

update_toml_version "$REPO_ROOT/APPS/JUST4PDF/pyproject.toml"
update_cfg_version "$REPO_ROOT/APPS/JUST4PDF/setup.cfg"

# Update packaging Info.plist for JUST4PDF (for manual builds/debugging).
PDF_PLIST="$REPO_ROOT/APPS/JUST4PDF/packaging/macos/Info.plist"
if [ -f "$PDF_PLIST" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SUITE_VERSION" "$PDF_PLIST" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $SUITE_VERSION" "$PDF_PLIST" 2>/dev/null || true
fi

echo "Synced versions to $SUITE_VERSION"
