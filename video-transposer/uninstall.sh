#!/bin/bash
#
# Removes the "Transpose audio" Finder Quick Action.

set -euo pipefail

DEST="$HOME/Library/Services/Transpose Audio.workflow"

if [ -d "$DEST" ]; then
  rm -rf "$DEST"
  echo "Removed $DEST"
else
  echo "Quick Action not installed, nothing to do."
fi
