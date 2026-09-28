#!/usr/bin/env bash
set -euo pipefail

# Los tests de rendimiento viven en PACKAGES/J4SHARED (los motores se movieron allí en 09-2026).
ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT_DIR/PACKAGES/J4SHARED"

echo "[j4f] Perf 100k — listado incremental (crea 100k ficheros temporales; puede tardar)…"
J4F_RUN_100K_PERF=1 swift test --filter J4FFileSystemTests/testListing100kFilesPerfWhenEnabled

echo "[j4f] Perf 100k — índice FTS5 (crawl + consultas; imprime «J4I PERF · …»)…"
J4I_RUN_100K_PERF=1 swift test --filter IndexPerformanceTests

echo "[j4f] Perf 100k completado."
