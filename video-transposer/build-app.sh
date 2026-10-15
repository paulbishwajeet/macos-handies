#!/bin/bash
#
# Builds build/Video Tools.app from app/Sources with the Command Line Tools
# swiftc (no Xcode project), arm64 only, ad-hoc signed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$SCRIPT_DIR/build/Video Tools.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -target arm64-apple-macos14 -O -parse-as-library \
  -o "$APP/Contents/MacOS/VideoTools" "$SCRIPT_DIR"/app/Sources/*.swift
cp "$SCRIPT_DIR/app/Info.plist" "$APP/Contents/Info.plist"
codesign --force -s - "$APP"

echo "Built $APP"
