#!/bin/zsh

set -euo pipefail

ROOT=${0:A:h:h}
APP_DIR="$ROOT/dist/SleepLatch.app"
ZIP_PATH="$ROOT/dist/SleepLatch.zip"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

export HOME=/tmp/swiftpm-home
export CLANG_MODULE_CACHE_PATH=/tmp/swift-module-cache

mkdir -p "$HOME" "$CLANG_MODULE_CACHE_PATH"

cd "$ROOT"
swift scripts/generate-app-icon.swift
swift build --disable-sandbox

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

cp "$ROOT/.build/debug/SleepLatch" "$MACOS_DIR/SleepLatch"
cp "$ROOT/AppResources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT/AppResources/SleepLatch.icns" "$RESOURCES_DIR/SleepLatch.icns"
chmod +x "$MACOS_DIR/SleepLatch"
codesign --force --deep --sign - "$APP_DIR"

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "Packaged app: $APP_DIR"
echo "Packaged zip: $ZIP_PATH"
