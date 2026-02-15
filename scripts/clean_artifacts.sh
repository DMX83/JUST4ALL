#!/bin/sh
set -e

cd "$(dirname "$0")/.."

safe_rm() {
	rm -rf "$@" 2>/dev/null || true
}

safe_rm build dist .build .swiftpm

safe_rm APPS/JUST4PDF/build APPS/JUST4PDF/dist APPS/JUST4PDF/.build
safe_rm APPS/JUST4CONVERT/build APPS/JUST4CONVERT/dist APPS/JUST4CONVERT/.build
