#!/bin/bash
#
# build-pkg.sh
#
# Assembles the Redact Personals Quick Action (including the
# self-contained redact-bin produced by build-binary.sh) into a single,
# double-clickable, unsigned .pkg installer. The package targets the
# current-user-home install domain only, so Installer.app runs it with
# no admin password, writing into ~/Library/Services exactly like
# install.sh does for the git-clone flow.
#
# Prerequisite: run ./build-binary.sh first.
# Output: pdf_redactor/packaging/build/RedactPersonals.pkg

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PDF_REDACTOR="$REPO_ROOT/pdf_redactor"
BUILD_DIR="$SCRIPT_DIR/build"
PAYLOAD_DIR="$BUILD_DIR/payload"
WORKFLOW_NAME="Redact Personals.workflow"
PKG_ID="com.aipathstudio.pdfredactor"
PKG_VERSION="1.0.0"

if [ ! -f "$BUILD_DIR/redact-bin" ]; then
  echo "error: $BUILD_DIR/redact-bin not found. Run ./build-binary.sh first." >&2
  exit 1
fi

echo "=== Assembling payload ==="
rm -rf "$PAYLOAD_DIR"
DEST="$PAYLOAD_DIR/Library/Services/$WORKFLOW_NAME"
mkdir -p "$DEST/Contents/Resources"
cp "$PDF_REDACTOR/$WORKFLOW_NAME/Contents/Info.plist" "$DEST/Contents/Info.plist"
cp "$PDF_REDACTOR/$WORKFLOW_NAME/Contents/document.wflow" "$DEST/Contents/document.wflow"
cp "$PDF_REDACTOR/scripts/redact-personals.sh" "$DEST/Contents/Resources/redact-personals.sh"
cp "$PDF_REDACTOR/scripts/redact.py" "$DEST/Contents/Resources/redact.py"
cp "$BUILD_DIR/redact-bin" "$DEST/Contents/Resources/redact-bin"
chmod +x "$DEST/Contents/Resources/redact-personals.sh" "$DEST/Contents/Resources/redact-bin"

echo "=== Building component package ==="
pkgbuild \
  --root "$PAYLOAD_DIR" \
  --identifier "$PKG_ID" \
  --version "$PKG_VERSION" \
  --install-location "/" \
  "$BUILD_DIR/RedactPersonalsComponent.pkg"

echo "=== Building product installer ==="
productbuild \
  --distribution "$SCRIPT_DIR/Distribution.xml" \
  --package-path "$BUILD_DIR" \
  "$BUILD_DIR/RedactPersonals.pkg"

echo "Done: $BUILD_DIR/RedactPersonals.pkg"
