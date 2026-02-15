#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$REPO_ROOT/scripts/app_env.sh"

TAG="v$APP_VERSION"

cd "$REPO_ROOT"

./scripts/sync_versions.sh

echo "Building subapp DMGs..."
(cd "$REPO_ROOT/APPS/JUST4CONVERT" && ./scripts/build_dmg.sh)
(cd "$REPO_ROOT/APPS/JUST4PDF" && ./packaging/build_dmg.sh)

echo "Preparing versioned release assets..."
./scripts/sync_local_dmgs.sh

ASSETS_DIR="$REPO_ROOT/dist/release-assets"
SUMS_FILE="$ASSETS_DIR/SHA256SUMS.txt"

(
  cd "$ASSETS_DIR"
  shasum -a 256 *.dmg > "$SUMS_FILE"
)

echo "Creating/updating GitHub Release $TAG..."
if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" "$ASSETS_DIR"/*.dmg "$SUMS_FILE" --clobber
else
  gh release create "$TAG" "$ASSETS_DIR"/*.dmg "$SUMS_FILE" \
    -t "JUST4ALL $TAG" \
    -n "Assets versionados para subapps + SHA256SUMS."
fi

echo "Release listo: $TAG"

