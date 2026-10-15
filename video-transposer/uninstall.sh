#!/bin/bash
#
# Removes Video Tools and its two Finder Quick Actions.

set -euo pipefail

APP="$HOME/Applications/Video Tools.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

for path in "$APP" \
            "$HOME/Library/Services/Transpose Audio.workflow" \
            "$HOME/Library/Services/Cut Video.workflow"; do
  if [ -d "$path" ]; then
    [ "$path" = "$APP" ] && "$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
    rm -rf "$path"
    echo "Removed $path"
  else
    echo "Not installed: $path"
  fi
done
/System/Library/CoreServices/pbs -flush
