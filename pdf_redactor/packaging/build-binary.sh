#!/bin/bash
#
# build-binary.sh
#
# Freezes pdf_redactor/scripts/redact.py into two self-contained,
# architecture-specific macOS executables (arm64 and x86_64) with no
# python3/pip dependency at runtime. Requires Xcode Command Line Tools
# (for the x86_64 leg, run under Rosetta 2 via `arch -x86_64`) and
# internet access to install PyMuPDF + PyInstaller for each architecture.
#
# NOTE: the two per-architecture binaries are shipped SIDE BY SIDE, not
# merged into a single "universal" binary via `lipo -create`. A
# PyInstaller --onefile binary is a Mach-O executable with a CArchive
# appended after the end of the image; the bootloader locates that
# archive by seeking backward from the end of the FILE. `lipo -create`
# concatenates the two architecture slices into one fat file, so only
# whichever slice's data lands last in the merged file has its trailing
# archive found correctly by its own bootloader -- the other slice's
# bootloader reads garbage and crashes. redact-personals.sh picks the
# correct per-arch binary at runtime via `uname -m`.
#
# Output:
#   pdf_redactor/packaging/build/redact-bin-arm64
#   pdf_redactor/packaging/build/redact-bin-x86_64

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REDACT_PY="$REPO_ROOT/pdf_redactor/scripts/redact.py"
BUILD_DIR="$SCRIPT_DIR/build"
WORK_DIR="$BUILD_DIR/pyinstaller-work"

# Pinned so both architectures freeze from known, consistent dependency
# versions instead of "whatever pip resolves today". pymupdf 1.26.5 ships
# a cp39-abi3 wheel, so it installs cleanly on both the Homebrew arm64
# python3 (3.14.x) and Apple's CommandLineTools x86_64 python3 (3.9.x).
PYMUPDF_VERSION="1.26.5"
PYINSTALLER_VERSION="6.22.3"

pip_install_compat() {
  local arch="$1"
  local python_bin="$2"
  shift 2
  local tmpfile rc=0
  tmpfile="$(mktemp)"
  if ! arch -"$arch" "$python_bin" -m pip install --user --quiet "$@" 2>"$tmpfile"; then
    if grep -qi "externally-managed-environment" "$tmpfile"; then
      arch -"$arch" "$python_bin" -m pip install --user --quiet --break-system-packages "$@" || rc=$?
    else
      cat "$tmpfile" >&2
      rc=1
    fi
  fi
  rm -f "$tmpfile"
  return "$rc"
}

build_arch() {
  local arch="$1"
  local python_bin="$2"
  local out_name="redact-bin-$arch"
  local work="$WORK_DIR/$arch"

  echo "=== Building $arch binary (using $python_bin) ==="
  mkdir -p "$work"
  cp "$REDACT_PY" "$work/redact.py"

  pip_install_compat "$arch" "$python_bin" "pymupdf==$PYMUPDF_VERSION" "pyinstaller==$PYINSTALLER_VERSION"

  (cd "$work" && arch -"$arch" "$python_bin" -m PyInstaller --onefile --name "$out_name" redact.py)

  cp "$work/dist/$out_name" "$BUILD_DIR/$out_name"
  chmod +x "$BUILD_DIR/$out_name"
  echo "=== $arch binary built: $BUILD_DIR/$out_name ==="
}

mkdir -p "$WORK_DIR"

build_arch "arm64" "python3"
build_arch "x86_64" "/usr/bin/python3"

echo "=== Verifying architectures ==="
file "$BUILD_DIR/redact-bin-arm64"
file "$BUILD_DIR/redact-bin-x86_64"

echo "=== Functionally verifying each binary redacts a real PDF natively ==="
VERIFY_DIR="$(mktemp -d)"
trap 'rm -rf "$VERIFY_DIR"' EXIT

make_test_pdf() {
  local out="$1"
  python3 - "$out" <<'PYEOF'
import sys
import pymupdf as fitz

path = sys.argv[1]
doc = fitz.open()
page = doc.new_page()
page.insert_text((72, 72), "Hello John Smith, this is a build verification PDF.", fontsize=12)
doc.save(path)
doc.close()
PYEOF
}

check_redacted() {
  local out="$1"
  python3 - "$out" <<'PYEOF'
import sys
import pymupdf as fitz

path = sys.argv[1]
doc = fitz.open(path)
text = "\n".join(page.get_text() for page in doc)
doc.close()
if "John" in text:
    print(f"VERIFY FAIL: 'John' still present in {path}", file=sys.stderr)
    sys.exit(1)
if "Hello" not in text:
    print(f"VERIFY FAIL: unrelated text 'Hello' missing from {path}", file=sys.stderr)
    sys.exit(1)
print(f"VERIFY OK: {path} redacted correctly")
PYEOF
}

make_test_pdf "$VERIFY_DIR/in.pdf"

echo "--- arm64 (native) ---"
arch -arm64 "$BUILD_DIR/redact-bin-arm64" "$VERIFY_DIR/in.pdf" "$VERIFY_DIR/out-arm64.pdf" John
check_redacted "$VERIFY_DIR/out-arm64.pdf"

echo "--- x86_64 (via Rosetta 2) ---"
arch -x86_64 "$BUILD_DIR/redact-bin-x86_64" "$VERIFY_DIR/in.pdf" "$VERIFY_DIR/out-x86_64.pdf" John
check_redacted "$VERIFY_DIR/out-x86_64.pdf"

echo "Done:"
echo "  $BUILD_DIR/redact-bin-arm64"
echo "  $BUILD_DIR/redact-bin-x86_64"
