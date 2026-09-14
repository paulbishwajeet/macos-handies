# PDF Redactor .pkg Installer + Branding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a small branding line to the Redact Personals dialog, and produce a self-contained, double-clickable, unsigned `.pkg` installer that installs the Quick Action with no Python/Homebrew/pip dependency on the recipient's machine.

**Architecture:** `redact.py` is frozen into a universal (arm64 + x86_64) standalone binary via PyInstaller + `lipo`. `redact-personals.sh` becomes binary-aware — it uses the frozen binary when present (the `.pkg` install), and falls back to `python3 redact.py` otherwise (the existing git-clone + `install.sh` flow), so one script serves both distribution paths. `pkgbuild`/`productbuild` assemble the workflow bundle (including the frozen binary) into a `.pkg` targeting the current-user-home install domain, so it needs no admin password.

**Tech Stack:** Bash, AppleScript (`osascript`), PyInstaller, `lipo`, `pkgbuild`/`productbuild`, XML (Distribution.xml).

## Global Constraints

- Branding text (exact, verbatim): `aipathstudio · https://aipathstudio.com`, shown as a second, separated line under the existing "Words to redact (comma-separated):" prompt in the same dialog (spec: Part A).
- Branding change applies to the one shared `pdf_redactor/scripts/redact-personals.sh` — both the git-clone `install.sh` flow and the `.pkg` flow use the identical script (spec: Part A).
- `redact-personals.sh` must use `Contents/Resources/redact-bin` when present and executable, falling back to `python3 redact.py` otherwise; the PyMuPDF-availability check only runs on the fallback path (spec: Part B, "redact-personals.sh becomes binary-aware").
- The frozen binary must be a universal binary covering both `arm64` and `x86_64` (spec: Part B, `build-binary.sh`).
- The `.pkg` must install into the current user's home directory (`~/Library/Services`) with no admin password required — `Distribution.xml` must declare `enable_localSystem="false" enable_currentUserHome="true" enable_anywhere="false"` (spec: Part B, `Distribution.xml`).
- Package identifier: `com.aipathstudio.pdfredactor` (spec: Part B, `build-pkg.sh`).
- No code signing / notarization (spec: Out of Scope — ships unsigned, per explicit decision).
- No `.pkg`-based uninstaller; document manual removal instead (spec: Out of Scope).
- Build artifacts (`packaging/build/`) are gitignored; only build scripts and docs are committed (spec: "New folder: pdf_redactor/packaging/").

---

## File Structure

```
pdf_redactor/
  scripts/
    redact-personals.sh   # MODIFY: branding + binary-aware dispatch
  packaging/
    build-binary.sh        # CREATE: freezes redact.py -> universal redact-bin
    build-pkg.sh            # CREATE: assembles payload, runs pkgbuild/productbuild
    Distribution.xml        # CREATE: user-domain-only install declaration
    README.md               # CREATE: build steps + recipient Gatekeeper note
    .gitignore               # CREATE: ignores build/
```

- `redact-personals.sh` keeps its single responsibility (dialog + orchestration) — the only new concept is "which redact command to run," gated by one `if [ -x ... ]` check.
- `build-binary.sh` owns turning Python source into a native binary; it knows nothing about packaging or Finder.
- `build-pkg.sh` owns assembling the installable payload and invoking Apple's packaging tools; it knows nothing about how the binary was built (just that it exists at a known path).
- `Distribution.xml` is pure declarative packaging metadata, no logic.

---

### Task 1: Branding + binary-aware dispatch in `redact-personals.sh`

**Files:**
- Modify: `pdf_redactor/scripts/redact-personals.sh`

**Interfaces:**
- Consumes: nothing new from other tasks — this task only needs to know the eventual binary will be named `redact-bin` and live in `Contents/Resources` next to this script (i.e. `$SCRIPT_DIR/redact-bin`), which Task 3 will place there when building the `.pkg`.
- Produces: `redact-personals.sh` with two changes: (1) the AppleScript dialog message includes the branding line, (2) a `REDACT_CMD` array that Tasks 3/4's end-to-end verification will rely on being correct — when `$SCRIPT_DIR/redact-bin` exists and is executable, `REDACT_CMD=("$SCRIPT_DIR/redact-bin")`; otherwise `REDACT_CMD=("$PYTHON_BIN" "$SCRIPT_DIR/redact.py")`.

This file has no automated test suite (it's bash + AppleScript, same as when it was originally built) — verification is manual, following the same style used when this script was first written.

- [ ] **Step 1: Add the branding line to the dialog message**

In `pdf_redactor/scripts/redact-personals.sh`, find this block:

```bash
  dialog_result=$(osascript <<EOF
try
  set userInput to text returned of (display dialog "Words to redact (comma-separated):" default answer "$escaped_default" with title "Redact Personals")
  return userInput
on error number -128
  return "__CANCELLED__"
end try
EOF
)
```

Replace the `display dialog` line so the message spans two lines inside
the same quoted AppleScript string (AppleScript string literals may
contain a literal newline directly in the source):

```bash
  dialog_result=$(osascript <<EOF
try
  set userInput to text returned of (display dialog "Words to redact (comma-separated):

aipathstudio · https://aipathstudio.com" default answer "$escaped_default" with title "Redact Personals")
  return userInput
on error number -128
  return "__CANCELLED__"
end try
EOF
)
```

- [ ] **Step 2: Add binary detection after `PYTHON_BIN` is set**

Find:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULTS_DOMAIN="com.macoshandies.pdfredactor"
PYTHON_BIN="${PDF_REDACTOR_PYTHON:-python3}"
```

Replace with:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULTS_DOMAIN="com.macoshandies.pdfredactor"
PYTHON_BIN="${PDF_REDACTOR_PYTHON:-python3}"

REDACT_BIN="$SCRIPT_DIR/redact-bin"
if [ -x "$REDACT_BIN" ]; then
  REDACT_CMD=("$REDACT_BIN")
else
  REDACT_CMD=("$PYTHON_BIN" "$SCRIPT_DIR/redact.py")
fi
```

- [ ] **Step 3: Skip the PyMuPDF check when the frozen binary is present**

Find:

```bash
if ! "$PYTHON_BIN" -c "import fitz" >/dev/null 2>&1; then
  alert "PyMuPDF is not installed. Please re-run install.sh for this Quick Action."
  exit 1
fi
```

Replace with:

```bash
if [ ! -x "$REDACT_BIN" ]; then
  if ! "$PYTHON_BIN" -c "import fitz" >/dev/null 2>&1; then
    alert "PyMuPDF is not installed. Please re-run install.sh for this Quick Action."
    exit 1
  fi
fi
```

- [ ] **Step 4: Use `REDACT_CMD` for the per-file invocation**

Find:

```bash
  if ! error_output=$("$PYTHON_BIN" "$SCRIPT_DIR/redact.py" "$input" "$output" "${words[@]}" 2>&1); then
    alert "Failed to redact \"$base\": $error_output"
  fi
```

Replace with:

```bash
  if ! error_output=$("${REDACT_CMD[@]}" "$input" "$output" "${words[@]}" 2>&1); then
    alert "Failed to redact \"$base\": $error_output"
  fi
```

- [ ] **Step 5: Manual verification — fallback path unchanged (no `redact-bin` present)**

Run (from the repo root, `pdf_redactor/scripts/` has no `redact-bin` file
at this point in the plan, so the fallback path is exercised):

```bash
python3 - <<'EOF'
import fitz
doc = fitz.open()
page = doc.new_page()
page.insert_text((72, 72), "Hello Alice Smith", fontsize=12)
doc.save("/tmp/branding-test.pdf")
EOF

pdf_redactor/scripts/redact-personals.sh --words "Alice" /tmp/branding-test.pdf
python3 -c "import fitz; print(fitz.open('/tmp/branding-test_Red.pdf').load_page(0).get_text())"
rm -f /tmp/branding-test.pdf /tmp/branding-test_Red.pdf
```

Expected: prints text with "Alice" removed, "Hello"/"Smith" intact —
identical behavior to before this task, confirming the fallback path
(`$PYTHON_BIN redact.py`) still works when `redact-bin` doesn't exist.

- [ ] **Step 6: Manual verification — binary path is preferred when present**

Run (creates a throwaway fake "binary" that just logs its invocation,
to prove `REDACT_CMD` picks it over the Python fallback, without needing
a real frozen binary yet — Task 2 builds the real one):

```bash
cat > /tmp/fake-redact-bin <<'EOF'
#!/bin/bash
echo "fake-binary-invoked:$*" > /tmp/fake-redact-bin.log
exit 0
EOF
chmod +x /tmp/fake-redact-bin
cp /tmp/fake-redact-bin pdf_redactor/scripts/redact-bin

PDF_REDACTOR_PYTHON=/nonexistent/does-not-exist pdf_redactor/scripts/redact-personals.sh --words "Alice" /tmp/does-not-need-to-exist.pdf
cat /tmp/fake-redact-bin.log

rm -f pdf_redactor/scripts/redact-bin /tmp/fake-redact-bin /tmp/fake-redact-bin.log
```

Expected: `/tmp/fake-redact-bin.log` contains a line starting with
`fake-binary-invoked:` followed by the input/output paths and `Alice` —
proving the script called the fake binary directly rather than trying
(and failing on) the intentionally-broken `PYTHON_BIN`, which confirms
the PyMuPDF-availability check is correctly skipped when `redact-bin` is
present. Also confirms `pdf_redactor/scripts/redact-bin` is removed
afterward (it must NOT be committed — Task 2 owns producing the real one
under `packaging/build/`, never inside `scripts/`).

- [ ] **Step 7: Manual verification — branding text appears in the dialog**

Run interactively (requires a real Finder/GUI session — skip if running
headless, but note that in your report):

```bash
pdf_redactor/scripts/redact-personals.sh /tmp/branding-test.pdf 2>/dev/null || true
```

(Recreate `/tmp/branding-test.pdf` first via Step 5's Python snippet if
needed.) Confirm visually that the dialog shows "Words to redact
(comma-separated):" followed by a blank line and then
"aipathstudio · https://aipathstudio.com". Press Cancel — confirm no
error and no file is created. Clean up `/tmp/branding-test.pdf` after.

- [ ] **Step 8: Commit**

```bash
git add pdf_redactor/scripts/redact-personals.sh
git commit -m "Add branding to redact dialog and make redact-personals.sh binary-aware"
```

---

### Task 2: `build-binary.sh` — freeze `redact.py` into a universal binary

**Files:**
- Create: `pdf_redactor/packaging/build-binary.sh`
- Create: `pdf_redactor/packaging/.gitignore`

**Interfaces:**
- Consumes: `pdf_redactor/scripts/redact.py`'s existing CLI (`redact.py <input.pdf> <output.pdf> <word1> [word2 ...]`, from the original implementation — unchanged by this plan).
- Produces: `pdf_redactor/packaging/build/redact-bin` — a universal (arm64 + x86_64) standalone executable implementing that exact same CLI, with no `python3`/pip dependency at runtime. Task 3 consumes this file at this exact path.

This is a build script with no unit-test framework; verification is
running it for real and inspecting/exercising its output, the same
approach used for `install.sh` in the original plan.

- [ ] **Step 1: Create `pdf_redactor/packaging/.gitignore`**

```
build/
```

- [ ] **Step 2: Create `pdf_redactor/packaging/build-binary.sh`**

```bash
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
```

- [ ] **Step 3: Make it executable**

Run: `chmod +x pdf_redactor/packaging/build-binary.sh`

- [ ] **Step 4: Run it and verify both architectures are present**

Run: `pdf_redactor/packaging/build-binary.sh`

Expected: completes without error; final `lipo -info` line reads
`Architectures in the fat file: .../redact-bin are: x86_64 arm64` (order
may vary). If the x86_64 leg fails because Rosetta 2 isn't installed,
the error will mention `arch: posix_spawn` or similar — in that case
run `softwareupdate --install-rosetta --agree-to-license` first and
re-run this step; note in your report if you had to do this.

- [ ] **Step 5: Verify the binary actually works standalone**

Run:

```bash
python3 - <<'EOF'
import fitz
doc = fitz.open()
page = doc.new_page()
page.insert_text((72, 72), "Universal Binary Test Carol", fontsize=12)
doc.save("/tmp/binary-test.pdf")
EOF

pdf_redactor/packaging/build/redact-bin /tmp/binary-test.pdf /tmp/binary-test-out.pdf Carol
python3 -c "import fitz; print(fitz.open('/tmp/binary-test-out.pdf').load_page(0).get_text())"
rm -f /tmp/binary-test.pdf /tmp/binary-test-out.pdf
```

Expected: prints text with "Carol" removed, "Universal Binary Test"
intact, confirming the frozen binary redacts correctly with the exact
same CLI contract as `redact.py`.

- [ ] **Step 6: Commit**

```bash
git add pdf_redactor/packaging/build-binary.sh pdf_redactor/packaging/.gitignore
git commit -m "Add build-binary.sh to freeze redact.py into a universal binary"
```

(`pdf_redactor/packaging/build/` is gitignored and correctly excluded —
verify with `git status` that no files from `build/` appear as
untracked-and-about-to-be-added.)

---

### Task 3: `build-pkg.sh` + `Distribution.xml` — assemble the `.pkg`

**Files:**
- Create: `pdf_redactor/packaging/build-pkg.sh`
- Create: `pdf_redactor/packaging/Distribution.xml`

**Interfaces:**
- Consumes: `pdf_redactor/packaging/build/redact-bin` (from Task 2, must already exist — this task's script checks for it and fails with a clear message if missing); `pdf_redactor/Redact Personals.workflow/Contents/{Info.plist,document.wflow}` and `pdf_redactor/scripts/{redact-personals.sh,redact.py}` (existing files, unchanged by this task).
- Produces: `pdf_redactor/packaging/build/RedactPersonals.pkg` — the final artifact Task 4's end-to-end verification installs and tests.

- [ ] **Step 1: Create `pdf_redactor/packaging/Distribution.xml`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>Redact Personals</title>
    <welcome mime-type="text/plain">This installs the "Redact Personals" Finder Quick Action.

After installing, right-click any PDF file in Finder and choose Quick Actions &gt; Redact Personals to use it.

No admin password is required -- this installs only into your own user account.</welcome>
    <options customize="never" require-scripts="false" rootVolumeOnly="false"/>
    <domains enable_localSystem="false" enable_currentUserHome="true" enable_anywhere="false"/>
    <choices-outline>
        <line choice="default">
            <line choice="com.aipathstudio.pdfredactor"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="com.aipathstudio.pdfredactor" visible="false">
        <pkg-ref id="com.aipathstudio.pdfredactor"/>
    </choice>
    <pkg-ref id="com.aipathstudio.pdfredactor">RedactPersonalsComponent.pkg</pkg-ref>
</installer-gui-script>
```

- [ ] **Step 2: Create `pdf_redactor/packaging/build-pkg.sh`**

```bash
#!/bin/bash
#
# build-pkg.sh
#
# Assembles the Redact Personals Quick Action (including the
# self-contained redact-bin produced by build-binary.sh) into a single,
# double-clickable, unsigned .pkg installer. The package targets the
# current-user-home install domain only, so Installer.app runs it with
# no admin password, writing into ~/Library/Services exactly like
# install.sh does for the git-clone flow.
#
# Prerequisite: run ./build-binary.sh first.
# Output: pdf_redactor/packaging/build/RedactPersonals.pkg

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PDF_REDACTOR="$REPO_ROOT/pdf_redactor"
BUILD_DIR="$SCRIPT_DIR/build"
PAYLOAD_DIR="$BUILD_DIR/payload"
WORKFLOW_NAME="Redact Personals.workflow"
PKG_ID="com.aipathstudio.pdfredactor"
PKG_VERSION="1.0.0"

if [ ! -f "$BUILD_DIR/redact-bin" ]; then
  echo "error: $BUILD_DIR/redact-bin not found. Run ./build-binary.sh first." >&2
  exit 1
fi

echo "=== Assembling payload ==="
rm -rf "$PAYLOAD_DIR"
DEST="$PAYLOAD_DIR/Library/Services/$WORKFLOW_NAME"
mkdir -p "$DEST/Contents/Resources"
cp "$PDF_REDACTOR/$WORKFLOW_NAME/Contents/Info.plist" "$DEST/Contents/Info.plist"
cp "$PDF_REDACTOR/$WORKFLOW_NAME/Contents/document.wflow" "$DEST/Contents/document.wflow"
cp "$PDF_REDACTOR/scripts/redact-personals.sh" "$DEST/Contents/Resources/redact-personals.sh"
cp "$PDF_REDACTOR/scripts/redact.py" "$DEST/Contents/Resources/redact.py"
cp "$BUILD_DIR/redact-bin" "$DEST/Contents/Resources/redact-bin"
chmod +x "$DEST/Contents/Resources/redact-personals.sh" "$DEST/Contents/Resources/redact-bin"

echo "=== Building component package ==="
pkgbuild \
  --root "$PAYLOAD_DIR" \
  --identifier "$PKG_ID" \
  --version "$PKG_VERSION" \
  --install-location "/" \
  "$BUILD_DIR/RedactPersonalsComponent.pkg"

echo "=== Building product installer ==="
productbuild \
  --distribution "$SCRIPT_DIR/Distribution.xml" \
  --package-path "$BUILD_DIR" \
  "$BUILD_DIR/RedactPersonals.pkg"

echo "Done: $BUILD_DIR/RedactPersonals.pkg"
```

- [ ] **Step 3: Make it executable**

Run: `chmod +x pdf_redactor/packaging/build-pkg.sh`

- [ ] **Step 4: Run it**

Run: `pdf_redactor/packaging/build-pkg.sh`

Expected: completes without error, prints
`Done: .../packaging/build/RedactPersonals.pkg`, and that file exists.

- [ ] **Step 5: Inspect the package contents without installing**

Run:

```bash
rm -rf /tmp/pkg-inspect
pkgutil --expand-full pdf_redactor/packaging/build/RedactPersonals.pkg /tmp/pkg-inspect
find /tmp/pkg-inspect -type f | sort
cat /tmp/pkg-inspect/Distribution
```

Expected: the file listing includes
`.../RedactPersonalsComponent.pkg/Payload/Library/Services/Redact Personals.workflow/Contents/Resources/redact-bin`
(exact nested path may vary slightly by `pkgutil` version, but the
`Library/Services/Redact Personals.workflow/Contents/Resources/{redact-bin,redact-personals.sh,redact.py}`
and `Contents/{Info.plist,document.wflow}` files must all be present),
and the `Distribution` file's content includes
`enable_currentUserHome="true"` and `enable_localSystem="false"`. Verify
`redact-bin` and `redact-personals.sh` are executable in the expanded
payload (`ls -la` on them, mode should include `x`). Clean up
`/tmp/pkg-inspect` after.

- [ ] **Step 6: Commit**

```bash
git add pdf_redactor/packaging/build-pkg.sh pdf_redactor/packaging/Distribution.xml
git commit -m "Add build-pkg.sh and Distribution.xml to assemble the .pkg installer"
```

---

### Task 4: `packaging/README.md` + end-to-end installer verification

**Files:**
- Create: `pdf_redactor/packaging/README.md`

**Interfaces:**
- Consumes: `pdf_redactor/packaging/build/RedactPersonals.pkg` (from Task 3).
- Produces: documentation, plus verified end-to-end proof that the built
  `.pkg` actually installs and runs a fully self-contained Quick Action.

- [ ] **Step 1: Write `pdf_redactor/packaging/README.md`**

```markdown
# Packaging: Redact Personals .pkg installer

Builds a single, double-clickable, self-contained `.pkg` for the
"Redact Personals" Finder Quick Action — no Python, Homebrew, or pip
required on the recipient's machine. The PDF redaction engine is frozen
into the package itself.

## Build

Prerequisites:
- Xcode Command Line Tools (`xcode-select --install`) for `pkgbuild` /
  `productbuild`.
- Rosetta 2, for building the x86_64 leg on Apple Silicon
  (`softwareupdate --install-rosetta --agree-to-license` if not already
  installed).
- Internet access (installs PyMuPDF + PyInstaller for each architecture
  automatically).

```bash
cd pdf_redactor/packaging
./build-binary.sh   # freezes redact.py into a universal (arm64 + x86_64) binary
./build-pkg.sh       # assembles the .pkg
```

Output: `pdf_redactor/packaging/build/RedactPersonals.pkg` — this is the
only file you need to share with a recipient. Nothing else from this
repo is required on their end.

## For recipients

This installer is **unsigned** (no Apple Developer ID). On first launch,
macOS Gatekeeper will likely block it. To open it anyway:

1. Right-click `RedactPersonals.pkg` and choose **Open** (instead of
   double-clicking), then confirm **Open** in the dialog that appears.
2. If it's still blocked, go to **System Settings > Privacy & Security**,
   scroll to the security section, and click **Open Anyway** next to the
   blocked-app message, then try opening the `.pkg` again.

The installer does not require an admin password — it installs only into
your own user account (`~/Library/Services`), not system-wide.

After installing, right-click any `.pdf` file in Finder and choose
**Quick Actions > Redact Personals**. If the menu item doesn't appear
immediately, log out and back in, or run:
`/System/Library/CoreServices/pbs -flush`

## Uninstall

There is no uninstaller `.pkg`. To remove it, delete:
`~/Library/Services/Redact Personals.workflow`
```

- [ ] **Step 2: End-to-end verification — back up any existing install first**

Check whether the Quick Action is already installed on this machine
(from earlier work) and preserve it before test-installing the new
`.pkg` over it:

```bash
if [ -d "$HOME/Library/Services/Redact Personals.workflow" ]; then
  echo "existing install found, backing up"
  rm -rf /tmp/redact-personals-workflow-backup
  cp -R "$HOME/Library/Services/Redact Personals.workflow" /tmp/redact-personals-workflow-backup
  EXISTED_BEFORE=1
else
  EXISTED_BEFORE=0
fi
echo "EXISTED_BEFORE=$EXISTED_BEFORE"
```

Note the value of `EXISTED_BEFORE` in your report — you'll use it in
Step 4 to decide how to restore state.

- [ ] **Step 3: Install the built `.pkg` via the command line (no GUI needed) and verify it needs no admin password**

Run:

```bash
installer -pkg pdf_redactor/packaging/build/RedactPersonals.pkg -target CurrentUserHomeDirectory
echo "install exit: $?"
ls -la "$HOME/Library/Services/Redact Personals.workflow/Contents/Resources/"
file "$HOME/Library/Services/Redact Personals.workflow/Contents/Resources/redact-bin"
```

Expected: exit code 0, no `sudo`/admin prompt was needed to run this
command (it's a plain user-level `installer` invocation), and the
`Contents/Resources/` directory contains `redact-bin`,
`redact-personals.sh`, and `redact.py`. `file` on `redact-bin` should
report a Mach-O binary (universal, both architectures) — confirming
`lipo`'s output survived being packaged and unpacked correctly.

- [ ] **Step 4: Run the installed Quick Action's script directly and confirm it uses the frozen binary, not Python**

Run:

```bash
python3 - <<'EOF'
import fitz
doc = fitz.open()
page = doc.new_page()
page.insert_text((72, 72), "Package Install Test Dave", fontsize=12)
doc.save("/tmp/pkg-e2e-test.pdf")
EOF

PDF_REDACTOR_PYTHON=/nonexistent/does-not-exist "$HOME/Library/Services/Redact Personals.workflow/Contents/Resources/redact-personals.sh" --words "Dave" /tmp/pkg-e2e-test.pdf
python3 -c "import fitz; print(fitz.open('/tmp/pkg-e2e-test_Red.pdf').load_page(0).get_text())"
rm -f /tmp/pkg-e2e-test.pdf /tmp/pkg-e2e-test_Red.pdf
```

Expected: succeeds and prints text with "Dave" removed, "Package Install
Test" intact — and critically, it succeeds *despite* `PDF_REDACTOR_PYTHON`
pointing at a nonexistent binary, proving the installed script used the
bundled `redact-bin`, not `python3`, confirming genuine zero-Python-
dependency operation for the `.pkg`-installed copy.

- [ ] **Step 5: Restore machine state**

```bash
rm -rf "$HOME/Library/Services/Redact Personals.workflow"
if [ "$EXISTED_BEFORE" = "1" ]; then
  cp -R /tmp/redact-personals-workflow-backup "$HOME/Library/Services/Redact Personals.workflow"
  echo "restored prior install"
else
  echo "left uninstalled (matches state before this task)"
fi
rm -rf /tmp/redact-personals-workflow-backup
```

Confirm in your report which branch was taken and that
`~/Library/Services` now matches its state from before Step 2.

- [ ] **Step 6: Commit**

```bash
git add pdf_redactor/packaging/README.md
git commit -m "Add packaging README and verify end-to-end .pkg install"
```

---

## Self-Review Notes

- Spec coverage: branding text and placement (Task 1 Steps 1, 7),
  shared-script-only branding scope (Task 1, entire task touches only
  the one shared file), binary-aware dispatch with fallback preserved
  (Task 1 Steps 2-6), universal binary build (Task 2), user-domain-only
  `.pkg` with no admin password (Task 3 Distribution.xml + Task 4 Step 3
  verification), package identifier (Task 3), unsigned/no notarization
  and no uninstaller (documented in Task 4's README, nothing built to
  contradict this), gitignored build artifacts (Task 2 Step 1) — all
  covered.
- No placeholders: every step has literal file contents or exact
  commands with concrete expected output.
- Type/interface consistency checked: `redact-bin`'s CLI contract
  (`<input> <output> <word...>`) matches `redact.py`'s existing CLI
  exactly (Task 2 builds a binary of the *same* script, no reimplementation);
  the path `$SCRIPT_DIR/redact-bin` referenced in Task 1's `REDACT_BIN`
  variable is the exact same relative location (`Contents/Resources/redact-bin`
  next to `redact-personals.sh`) that Task 3's `build-pkg.sh` copies the
  binary to — verified by both tasks' text referring to the identical
  `Contents/Resources/` layout used by the original `install.sh`.
