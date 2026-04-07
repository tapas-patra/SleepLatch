#!/bin/zsh

set -euo pipefail

ROOT=${0:A:h:h}
DOCS_DIR="$ROOT/docs"
DOWNLOADS_DIR="$DOCS_DIR/downloads"
SOURCE_ZIP="$ROOT/dist/SleepLatch.zip"
CHECKSUM_FILE="$DOWNLOADS_DIR/SHA256SUMS.txt"

zsh "$ROOT/scripts/package-sleeplatch.sh"

mkdir -p "$DOWNLOADS_DIR"
cp "$SOURCE_ZIP" "$DOWNLOADS_DIR/SleepLatch.zip"

(
    cd "$DOWNLOADS_DIR"
    shasum -a 256 "SleepLatch.zip" > "$CHECKSUM_FILE"
)

echo "Prepared GitHub Pages assets in $DOWNLOADS_DIR"
