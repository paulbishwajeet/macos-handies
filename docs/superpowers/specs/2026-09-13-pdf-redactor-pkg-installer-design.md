# PDF Redactor — Self-Contained .pkg Installer + Branding

## Purpose

Two additions to the existing `pdf_redactor` Finder Quick Action
("Redact Personals"):

1. **Branding**: the words-to-redact dialog shows a small "aipathstudio ·
   https://aipathstudio.com" line so recipients know who made it.
2. **Shareable installer**: a single, double-clickable `.pkg` that
   installs the Quick Action with zero dependency on the recipient's
   Python/Homebrew/pip setup — the redaction engine is frozen into the
   package itself, so it works on a fresh Mac that has never touched
   Python.

Feasibility of freezing `redact.py` into a standalone macOS binary (via
PyInstaller) and merging arm64 + x86_64 builds into one universal binary
via `lipo` was validated directly on this machine before writing this
spec: a frozen binary ran standalone (no `python3`/pip) and correctly
redacted a test PDF; `lipo -create` on an arm64 and an x86_64 PyInstaller
build produced a working "Architectures in the fat file: ... x86_64
arm64" binary.

## Part A — Branding

`pdf_redactor/scripts/redact-personals.sh`'s AppleScript `display dialog`
message changes from a single line to two lines — the existing prompt,
a blank line, then the branding:

```
Words to redact (comma-separated):

aipathstudio · https://aipathstudio.com
```

This is plain text (AppleScript's `display dialog` has no support for
clickable links or corner-anchored text) and applies to the *shared*
script — both the existing git-clone + `install.sh` flow and the new
`.pkg` flow show the same branded dialog. There is exactly one
`redact-personals.sh` to maintain.

## Part B — Self-Contained `.pkg`

### New folder: `pdf_redactor/packaging/`

```
pdf_redactor/packaging/
  build-binary.sh   # freezes redact.py into a universal redact-bin
  build-pkg.sh      # assembles payload, runs pkgbuild/productbuild
  Distribution.xml  # user-domain-only install declaration
  README.md         # build steps + recipient Gatekeeper note
  .gitignore        # ignores build/ (binaries, .pkg output)
```

Nothing under `packaging/build/` is committed — PyInstaller binaries and
the final `.pkg` are build artifacts, not source.

### `build-binary.sh`

1. Builds an arm64 binary: `arch -arm64 python3 -m PyInstaller --onefile
   --name redact-bin-arm64 pdf_redactor/scripts/redact.py` (using
   whatever `python3` is on PATH, native arm64 on Apple Silicon).
2. Builds an x86_64 binary the same way but via `arch -x86_64
   /usr/bin/python3` (Apple's universal system Python run under Rosetta
   2), after `arch -x86_64 /usr/bin/python3 -m pip install --user pymupdf
   pyinstaller` for that slice. Both steps were validated directly:
   `arch -x86_64 /usr/bin/python3 --version` reports 3.9.6 and runs; pip
   install and PyInstaller both succeeded under it, producing a genuine
   `Mach-O 64-bit executable x86_64`.
3. Merges the two with `lipo -create <arm64-binary> <x86_64-binary>
   -output packaging/build/redact-bin`.
4. Prints a `lipo -info` confirmation showing both architectures are
   present, and fails loudly (non-zero exit) if either per-arch build or
   the merge fails.

### `redact-personals.sh` becomes binary-aware

Add near the top (after `SCRIPT_DIR` is resolved):

```bash
REDACT_BIN="$SCRIPT_DIR/redact-bin"
if [ -x "$REDACT_BIN" ]; then
  REDACT_CMD=("$REDACT_BIN")
else
  REDACT_CMD=("$PYTHON_BIN" "$SCRIPT_DIR/redact.py")
fi
```

The PyMuPDF-availability check (`"$PYTHON_BIN" -c "import fitz"`) only
runs when falling back to the Python path — when `redact-bin` is present
(the `.pkg` install), that check is skipped since the binary is
self-contained by construction. The per-file invocation changes from
`"$PYTHON_BIN" "$SCRIPT_DIR/redact.py" "$input" "$output" "${words[@]}"`
to `"${REDACT_CMD[@]}" "$input" "$output" "${words[@]}"`.

This is the *only* runtime-behavior change to the script beyond Part A's
branding; the git-clone + `install.sh` flow is unaffected because
`install.sh` never places a `redact-bin` file, so the fallback path is
always taken there, unchanged from today.

### `build-pkg.sh`

1. Runs `build-binary.sh` (or requires it already ran; fails with a clear
   message if `packaging/build/redact-bin` is missing).
2. Assembles a payload directory mirroring the final install location:
   `packaging/build/payload/Library/Services/Redact Personals.workflow/`
   containing `Contents/Info.plist`, `Contents/document.wflow`, and
   `Contents/Resources/{redact-personals.sh, redact.py, redact-bin}` —
   the same files `install.sh` copies today, plus the new `redact-bin`.
   `redact-personals.sh` is `chmod +x`, `redact-bin` is `chmod +x`.
3. Runs `pkgbuild --root packaging/build/payload --identifier
   com.aipathstudio.pdfredactor --version <version> --install-location /
   packaging/build/RedactPersonalsComponent.pkg` (root already contains
   the full `Library/Services/...` path, so `--install-location /` maps
   it directly under the install domain's root — the user's home
   directory, per the Distribution.xml domain declaration below).
4. Runs `productbuild --distribution pdf_redactor/packaging/Distribution.xml
   --package-path packaging/build packaging/build/RedactPersonals.pkg`.
5. Prints the final path to `RedactPersonals.pkg` — this is the one file
   to share with a recipient.

### `Distribution.xml`

Declares:
- `<pkg-ref id="com.aipathstudio.pdfredactor">RedactPersonalsComponent.pkg</pkg-ref>`
- `<options customize="never" rootVolumeOnly="false"/>`
- `<domains enable_localSystem="false" enable_currentUserHome="true"
  enable_anywhere="false"/>` — this is what lets Installer.app offer a
  no-admin-password, "install for me only" flow that writes into the
  invoking user's `~/Library/Services`, matching `install.sh`'s existing
  per-user install location exactly.
- A minimal `<title>`/`<welcome>` referencing a short message (e.g. "This
  installs the Redact Personals Finder Quick Action. Right-click any PDF
  after installing to use it.").
- `<choices-outline>` / `<choice>` wiring the single component pkg as the
  only (non-customizable) choice.

### `packaging/README.md`

Documents:
- How to build: prerequisites (Xcode Command Line Tools for
  `pkgbuild`/`productbuild`; Rosetta 2 for the x86_64 build leg; PyMuPDF
  + PyInstaller installed per-architecture as `build-binary.sh` handles
  automatically), then `./build-pkg.sh`.
- What to share: only `packaging/build/RedactPersonals.pkg` — nothing
  else from the repo is needed by the recipient.
- Recipient instructions: since the `.pkg` is unsigned (no Apple
  Developer ID), first launch will be blocked by Gatekeeper. Recipients
  right-click the `.pkg` → Open (or, if blocked entirely, approve it via
  System Settings → Privacy & Security → "Open Anyway" after the first
  blocked attempt), then follow the normal Installer.app flow.
- Uninstall: no `.pkg`-based uninstaller is provided (out of scope,
  no user-visible way to invoke one anyway) — recipients remove it by
  deleting `~/Library/Services/Redact Personals.workflow`.

## Out of Scope

- Code signing / notarization (no Apple Developer ID available; ships
  unsigned per explicit decision).
- A `.pkg`-based or scripted uninstaller.
- Any UI beyond a plain-text branding line in the existing AppleScript
  dialog — no custom app window, no clickable link.
- Windows/Linux or any non-macOS distribution format.

## Testing Plan

- `build-binary.sh`: run it, confirm `lipo -info` on the output reports
  both `arm64` and `x86_64`, and confirm the binary redacts a
  PyMuPDF-generated test PDF correctly when invoked directly (no
  `python3`/pip involved), matching the standalone validation already
  performed manually before writing this spec.
- `redact-personals.sh`'s fallback logic: with no `redact-bin` present
  (today's install.sh layout), confirm it still calls `python3 redact.py`
  exactly as before — no regression to the existing git-clone flow.
  With a `redact-bin` present, confirm it's invoked instead and the
  Python-availability check is skipped.
- `build-pkg.sh`: run it, then use `pkgutil --expand-full` on the
  resulting `.pkg` to inspect the payload without installing, confirming
  `Library/Services/Redact Personals.workflow/Contents/Resources/redact-bin`
  is present and executable, and that `Distribution.xml`'s domain
  declaration matches what was specified.
- End-to-end (manual): install the built `.pkg` via Installer.app on this
  machine (a fresh `~/Library/Services` state, or removing any existing
  install first), confirm it installs without an admin password prompt,
  confirm the Quick Action appears for `.pdf` files after the usual
  Finder-registration refresh, and confirm running it against a real PDF
  redacts successfully with no `python3`/pip involved at runtime.
- Branding: confirm the dialog shows the two-line message including
  "aipathstudio · https://aipathstudio.com" both via the git-clone
  `install.sh` path and via the `.pkg` path (same script, so one
  verification covers both, but confirm both code paths still function
  correctly around the added binary-detection logic).
