#!/bin/bash
#
# Installs the "Transpose audio" Finder Quick Action.
#
# - Ensures Homebrew is available
# - Installs ffmpeg
# - Copies the Quick Action into ~/Library/Services
# - Copies transpose-audio.sh into the Quick Action bundle's Resources

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICES_DIR="$HOME/Library/Services"
WORKFLOW_NAME="Transpose Audio.workflow"
DEST="$SERVICES_DIR/$WORKFLOW_NAME"

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required but not installed."
  echo "Install it from https://brew.sh and re-run this script."
  exit 1
fi

echo "Installing dependency (ffmpeg)..."
brew install ffmpeg

mkdir -p "$SERVICES_DIR"
echo "Installing Quick Action to $DEST..."
rm -rf "$DEST"
cp -R "$SCRIPT_DIR/$WORKFLOW_NAME" "$DEST"

mkdir -p "$DEST/Contents/Resources"
cp "$SCRIPT_DIR/scripts/transpose-audio.sh" "$DEST/Contents/Resources/transpose-audio.sh"
chmod +x "$DEST/Contents/Resources/transpose-audio.sh"

echo "Done. Right-click a video file in Finder and choose"
echo "Quick Actions > Transpose audio."
echo
echo "If it doesn't show up immediately, log out and back in, or run:"
echo "  /System/Library/CoreServices/pbs -flush"
