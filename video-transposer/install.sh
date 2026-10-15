#!/bin/bash
#
# Installs Video Tools and its two Finder Quick Actions.
#
# - Ensures Homebrew is available and installs ffmpeg
# - Builds Video Tools.app and copies it to ~/Applications
# - Registers it with LaunchServices so videotools:// URLs open it
# - Copies "Transpose Audio" and "Cut Video" into ~/Library/Services

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICES_DIR="$HOME/Library/Services"
APP_NAME="Video Tools.app"
APP_DEST="$HOME/Applications/$APP_NAME"
WORKFLOWS=("Transpose Audio.workflow" "Cut Video.workflow")
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required but not installed."
  echo "Install it from https://brew.sh and re-run this script."
  exit 1
fi

echo "Installing dependency (ffmpeg)..."
brew install ffmpeg

echo "Building $APP_NAME..."
"$SCRIPT_DIR/build-app.sh"

echo "Installing app to $APP_DEST..."
mkdir -p "$HOME/Applications"
rm -rf "$APP_DEST"
cp -R "$SCRIPT_DIR/build/$APP_NAME" "$APP_DEST"
# Only the installed copy should answer videotools:// URLs. Building
# registers the build copy with LaunchServices on its own, so remove it.
"$LSREGISTER" -u "$SCRIPT_DIR/build/$APP_NAME" >/dev/null 2>&1 || true
rm -rf "$SCRIPT_DIR/build/$APP_NAME"
"$LSREGISTER" -f "$APP_DEST"

mkdir -p "$SERVICES_DIR"
for workflow in "${WORKFLOWS[@]}"; do
  echo "Installing Quick Action to $SERVICES_DIR/$workflow..."
  rm -rf "$SERVICES_DIR/$workflow"
  cp -R "$SCRIPT_DIR/$workflow" "$SERVICES_DIR/$workflow"
done
/System/Library/CoreServices/pbs -flush

echo "Done. Right-click a video file in Finder and choose"
echo "Quick Actions > Transpose audio or Quick Actions > Cut video."
echo
echo "If they don't show up immediately, log out and back in."
