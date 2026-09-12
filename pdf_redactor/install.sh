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

# Finder Quick Actions run redact-personals.sh with a minimal PATH that it
# then prepends with this same value (see that script's `export PATH=...`
# line). We must install PyMuPDF for the exact `python3` that resolves
# under that PATH, otherwise the interpreter this installer uses to pip
# install may differ from the one the Quick Action invokes at runtime,
# leaving PyMuPDF invisible to it.
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/Library/Python/3.9/bin:$PATH"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required but not installed."
  echo "Install Python 3 (e.g. via https://brew.sh: brew install python3) and re-run this script."
  exit 1
fi

echo "Using python3 at: $(command -v python3)"
echo "Installing dependency (PyMuPDF)..."
python3 -m pip install --user --break-system-packages pymupdf

echo "Verifying PyMuPDF is importable by the same python3 the Quick Action will use..."
if ! python3 -c "import fitz" >/dev/null 2>&1; then
  echo "ERROR: Installed PyMuPDF for $(command -v python3), but 'import fitz' failed" \
       "when checked under the same PATH the Quick Action uses" \
       "(/opt/homebrew/bin:/usr/local/bin:\$HOME/Library/Python/3.9/bin:\$PATH)."
  echo "This usually means there are multiple python3 interpreters installed" \
       "(e.g. Homebrew Python and python.org Python) and pip installed PyMuPDF" \
       "into a different one than what resolves at runtime."
  echo "Check 'which -a python3' and make sure the one PyMuPDF was installed for" \
       "is the one that resolves first on that PATH, then re-run this script."
  exit 1
fi

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
