#!/bin/zsh

set -euo pipefail

ROOT=${0:A:h:h}
APP_DIR="$ROOT/dist/SleepLatch.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

export HOME=/tmp/swiftpm-home
export CLANG_MODULE_CACHE_PATH=/tmp/swift-module-cache

mkdir -p "$HOME" "$CLANG_MODULE_CACHE_PATH"

cd "$ROOT"
swift build --disable-sandbox

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cp "$ROOT/.build/debug/SleepLatch" "$MACOS_DIR/SleepLatch"
cp "$ROOT/AppResources/Info.plist" "$CONTENTS_DIR/Info.plist"
chmod +x "$MACOS_DIR/SleepLatch"
codesign --force --deep --sign - "$APP_DIR"

echo "Packaged app: $APP_DIR"
