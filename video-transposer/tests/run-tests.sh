#!/bin/bash
#
# Compiles VideoEngine.swift with EngineTests.swift into a throwaway binary
# and runs it. Exits non-zero if any check fails. Needs ffmpeg installed.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

swiftc -target arm64-apple-macos14 -parse-as-library -o "$BUILD_DIR/engine-tests" \
  "$TESTS_DIR/../app/Sources/VideoEngine.swift" "$TESTS_DIR/EngineTests.swift"
"$BUILD_DIR/engine-tests"
