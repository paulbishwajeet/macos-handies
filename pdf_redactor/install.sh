#!/bin/bash
#
# Installs the "Redact Personals" Finder Quick Action.
#
# - Ensures python3 is available
# - Installs PyMuPDF via pip
# - Copies the Quick Action into ~/Library/Services
# - Copies redact.py and redact-personals.sh into the Quick Action bundle's Resources

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICES_DIR="$HOME/Library/Services"
WORKFLOW_NAME="Redact Personals.workflow"
DEST="$SERVICES_DIR/$WORKFLOW_NAME"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required but not installed."
  echo "Install Python 3 (e.g. via https://brew.sh: brew install python3) and re-run this script."
  exit 1
fi

echo "Installing dependency (PyMuPDF)..."
python3 -m pip install --user pymupdf

mkdir -p "$SERVICES_DIR"
echo "Installing Quick Action to $DEST..."
rm -rf "$DEST"
cp -R "$SCRIPT_DIR/$WORKFLOW_NAME" "$DEST"

mkdir -p "$DEST/Contents/Resources"
cp "$SCRIPT_DIR/scripts/redact.py" "$DEST/Contents/Resources/redact.py"
cp "$SCRIPT_DIR/scripts/redact-personals.sh" "$DEST/Contents/Resources/redact-personals.sh"
chmod +x "$DEST/Contents/Resources/redact-personals.sh"

echo "Done. Right-click a .pdf file in Finder and choose"
echo "Quick Actions > Redact Personals."
echo
echo "If it doesn't show up immediately, log out and back in, or run:"
echo "  /System/Library/CoreServices/pbs -flush"
