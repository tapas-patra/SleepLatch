#!/bin/zsh

set -euo pipefail

ROOT=${0:A:h:h}
OUT_DIR=/tmp/sleeplatch-smoke
SMOKE_BINARY="$OUT_DIR/SleepLatchSmokeCheck"

export CLANG_MODULE_CACHE_PATH=/tmp/swift-module-cache

mkdir -p "$OUT_DIR" "$CLANG_MODULE_CACHE_PATH"

swiftc \
    "$ROOT/Sources/SleepLatch/CaffeinateModels.swift" \
    "$ROOT/Sources/SleepLatch/CaffeinateSessionController.swift" \
    "$ROOT/Verification/SessionSmokeCheck.swift" \
    -o "$SMOKE_BINARY"

"$SMOKE_BINARY"
