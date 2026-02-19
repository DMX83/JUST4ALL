#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "[j4f] Running 100k listing perf test (this may take a while)..."
J4F_RUN_100K_PERF=1 swift test --filter J4FFileSystemTests/testListing100kFilesPerfWhenEnabled
echo "[j4f] 100k listing perf test completed."
