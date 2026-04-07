#!/bin/zsh

set -euo pipefail

ROOT=${0:A:h:h}

export HOME=/tmp/swiftpm-home
export CLANG_MODULE_CACHE_PATH=/tmp/swift-module-cache

mkdir -p "$HOME" "$CLANG_MODULE_CACHE_PATH"

cd "$ROOT"
swift run --disable-sandbox SleepLatch
