#!/bin/bash
#
# build-binary.sh
#
# Freezes pdf_redactor/scripts/redact.py into a single, self-contained,
# universal (arm64 + x86_64) macOS executable with no python3/pip
# dependency at runtime. Requires Xcode Command Line Tools (for the
# x86_64 leg, run under Rosetta 2 via `arch -x86_64`) and internet
# access to install PyMuPDF + PyInstaller for each architecture.
#
# Output: pdf_redactor/packaging/build/redact-bin

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REDACT_PY="$REPO_ROOT/pdf_redactor/scripts/redact.py"
BUILD_DIR="$SCRIPT_DIR/build"
WORK_DIR="$BUILD_DIR/pyinstaller-work"

pip_install_compat() {
  local arch="$1"
  local python_bin="$2"
  shift 2
  if ! arch -"$arch" "$python_bin" -m pip install --user --quiet "$@" 2>/tmp/pip-install-err.$$; then
    if grep -qi "externally-managed-environment" /tmp/pip-install-err.$$; then
      arch -"$arch" "$python_bin" -m pip install --user --quiet --break-system-packages "$@"
    else
      cat /tmp/pip-install-err.$$ >&2
      rm -f /tmp/pip-install-err.$$
      return 1
    fi
  fi
  rm -f /tmp/pip-install-err.$$
}

build_arch() {
  local arch="$1"
  local python_bin="$2"
  local out_name="redact-bin-$arch"
  local work="$WORK_DIR/$arch"

  echo "=== Building $arch binary (using $python_bin) ==="
  mkdir -p "$work"
  cp "$REDACT_PY" "$work/redact.py"

  pip_install_compat "$arch" "$python_bin" pymupdf pyinstaller

  (cd "$work" && arch -"$arch" "$python_bin" -m PyInstaller --onefile --name "$out_name" redact.py)

  cp "$work/dist/$out_name" "$BUILD_DIR/$out_name"
  echo "=== $arch binary built: $BUILD_DIR/$out_name ==="
}

mkdir -p "$WORK_DIR"

build_arch "arm64" "python3"
build_arch "x86_64" "/usr/bin/python3"

echo "=== Merging into universal binary ==="
lipo -create "$BUILD_DIR/redact-bin-arm64" "$BUILD_DIR/redact-bin-x86_64" -output "$BUILD_DIR/redact-bin"
chmod +x "$BUILD_DIR/redact-bin"

echo "=== Verifying architectures ==="
lipo -info "$BUILD_DIR/redact-bin"

echo "Done: $BUILD_DIR/redact-bin"
