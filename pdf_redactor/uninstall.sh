#!/bin/bash
#
# Removes the "Redact Personals" Finder Quick Action.

set -euo pipefail

SERVICES_DIR="$HOME/Library/Services"
WORKFLOW_NAME="Redact Personals.workflow"
DEST="$SERVICES_DIR/$WORKFLOW_NAME"

if [ -d "$DEST" ]; then
  rm -rf "$DEST"
  echo "Removed $DEST"
else
  echo "Not installed at $DEST"
fi
