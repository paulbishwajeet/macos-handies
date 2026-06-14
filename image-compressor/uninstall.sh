#!/bin/bash
#
# Removes the "Compress Image" Finder Quick Action.

set -euo pipefail

DEST="$HOME/Library/Services/Compress Image.workflow"

if [ -d "$DEST" ]; then
  rm -rf "$DEST"
  echo "Removed $DEST"
else
  echo "Quick Action not installed, nothing to do."
fi
