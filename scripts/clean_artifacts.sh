#!/bin/sh
set -e

cd "$(dirname "$0")/.."

safe_rm() {
	rm -rf "$@" 2>/dev/null || true
}

safe_rm build dist .build .swiftpm

safe_rm APPS/JUST4PDF/build APPS/JUST4PDF/dist APPS/JUST4PDF/.build
safe_rm APPS/JUST4CONVERT/build APPS/JUST4CONVERT/dist APPS/JUST4CONVERT/.build
safe_rm APPS/JUST4FOLDERS/build APPS/JUST4FOLDERS/dist APPS/JUST4FOLDERS/.build
safe_rm APPS/JUST4PICT/build APPS/JUST4PICT/dist APPS/JUST4PICT/.build
safe_rm APPS/JUST4DESK/build APPS/JUST4DESK/dist APPS/JUST4DESK/.build
