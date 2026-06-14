#!/bin/bash
#
# Installs the "Compress Image" Finder Quick Action.
#
# - Ensures Homebrew is available
# - Installs pngquant and jpegoptim
# - Copies the Quick Action into ~/Library/Services
# - Copies compress-image.sh into the Quick Action bundle's Resources

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICES_DIR="$HOME/Library/Services"
WORKFLOW_NAME="Compress Image.workflow"
DEST="$SERVICES_DIR/$WORKFLOW_NAME"

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required but not installed."
  echo "Install it from https://brew.sh and re-run this script."
  exit 1
fi

echo "Installing dependencies (pngquant, jpegoptim)..."
brew install pngquant jpegoptim

mkdir -p "$SERVICES_DIR"
echo "Installing Quick Action to $DEST..."
rm -rf "$DEST"
cp -R "$SCRIPT_DIR/$WORKFLOW_NAME" "$DEST"

mkdir -p "$DEST/Contents/Resources"
cp "$SCRIPT_DIR/scripts/compress-image.sh" "$DEST/Contents/Resources/compress-image.sh"
chmod +x "$DEST/Contents/Resources/compress-image.sh"

echo "Done. Right-click a .jpg or .png file in Finder and choose"
echo "Quick Actions > Compress Image."
echo
echo "If it doesn't show up immediately, log out and back in, or run:"
echo "  /System/Library/CoreServices/pbs -flush"
