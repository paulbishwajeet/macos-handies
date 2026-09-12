# PDF Redactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a Finder Quick Action, "Redact Personals", that appears only
on `.pdf` files and produces a `_Red.pdf` copy with user-specified words
permanently redacted (text removed, not just covered).

**Architecture:** An Automator Quick Action (`Redact Personals.workflow`)
restricted to PDFs via `NSSendFileTypes: com.adobe.pdf` runs a shell script
(`redact-personals.sh`) once per invocation. That script shows one
AppleScript dialog (pre-filled with the last-used value via `defaults`),
then shells out to a Python script (`redact.py`, built on PyMuPDF) once per
selected PDF to do the actual text search-and-redact.

**Tech Stack:** Bash, AppleScript (`osascript`), Python 3 + PyMuPDF
(`fitz`), Automator workflow bundle (Info.plist + document.wflow), pytest
for the Python unit tests.

## Global Constraints

- New top-level folder: `pdf_redactor/` (spec: "Folder layout").
- Match mode: case-insensitive substring match (spec: "Purpose" / clarifying answers).
- Output filename: `<name>_Red.pdf` in the same directory as the original, original never modified (spec: "User flow" step 7).
- Re-running overwrites an existing `_Red.pdf` (spec: "User flow" step 7).
- One dialog per invocation applies to all selected PDFs (spec: "User flow" step 2).
- Last-used comma-separated string persists via `defaults` under domain `com.macoshandies.pdfredactor`, key `lastWords` (spec: "User flow" steps 2-4).
- Words with no matches anywhere are silently ignored, no error (spec: "User flow" step 8).
- Empty/whitespace-only input after trimming aborts with an alert, no files created (spec: "Error handling").
- Missing/broken PyMuPDF import aborts with an alert telling the user to re-run `install.sh` (spec: "Error handling").
- A per-file processing failure is reported via alert but does not stop processing of remaining files (spec: "Error handling").
- `install.sh` installs PyMuPDF via `pip3 install --user pymupdf` (no Homebrew formula) (spec: "Dependencies / install").
- Out of scope: OCR/scanned-image text, coordinate-based redaction, non-text content beyond what `apply_redactions()` covers (spec: "Out of scope").

---

## File Structure

```
pdf_redactor/
  scripts/
    redact.py              # core redaction logic + CLI entrypoint
    redact-personals.sh    # dialog + defaults + per-file orchestration
  tests/
    test_redact.py         # pytest unit tests for redact.py
  Redact Personals.workflow/
    Contents/
      Info.plist            # NSServices entry, restricted to com.adobe.pdf
      document.wflow         # single Run Shell Script action
  install.sh                # pip install + copy workflow + copy scripts into bundle
  uninstall.sh               # remove workflow from ~/Library/Services
  README.md                  # usage docs for this utility
README.md                    # (repo root) add pdf_redactor to the utilities list
```

- `redact.py` owns all PDF manipulation logic and is unit-testable in isolation (no Finder/AppleScript involved).
- `redact-personals.sh` owns all user-interaction/orchestration (dialog, persistence, looping over files, error alerts) and is a thin shell around `redact.py`.
- The workflow bundle only wires Finder to `redact-personals.sh`; it contains no logic of its own, matching `image-compressor`'s pattern.

---

### Task 1: Core redaction logic (`redact.py`) with unit tests

**Files:**
- Create: `pdf_redactor/scripts/redact.py`
- Create: `pdf_redactor/tests/test_redact.py`

**Interfaces:**
- Produces: `redact_pdf(input_path: str, output_path: str, words: list[str]) -> None` — opens `input_path`, for each page does a case-insensitive substring search for each non-empty word in `words`, redacts every match (removes underlying text, paints a black box), and writes the result to `output_path`. Raises no exception for words with zero matches. Leaves `input_path` untouched.
- Produces: CLI entrypoint `python3 redact.py <input.pdf> <output.pdf> <word1> [word2 ...]` that calls `redact_pdf` and exits non-zero with a message on `stderr` if `input_path` doesn't exist or PyMuPDF fails to open it.

- [ ] **Step 1: Install dev dependencies**

Run: `python3 -m pip install --user pymupdf pytest`

This installs PyMuPDF (the production dependency, also needed for
`install.sh` later) and pytest (dev-only, for running these tests).

- [ ] **Step 2: Write the failing tests**

Create `pdf_redactor/tests/test_redact.py`:

```python
import subprocess
import sys
from pathlib import Path

import fitz
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
from redact import redact_pdf


def make_pdf(path, lines):
    doc = fitz.open()
    page = doc.new_page()
    y = 72
    for line in lines:
        page.insert_text((72, y), line, fontsize=12)
        y += 20
    doc.save(str(path))
    doc.close()


def extract_text(path):
    doc = fitz.open(str(path))
    text = "\n".join(page.get_text() for page in doc)
    doc.close()
    return text


def test_redacts_exact_word(tmp_path):
    src = tmp_path / "in.pdf"
    out = tmp_path / "out.pdf"
    make_pdf(src, ["Hello John Smith", "Nothing else here"])

    redact_pdf(str(src), str(out), ["John"])

    result = extract_text(out)
    assert "John" not in result
    assert "Hello" in result
    assert "Smith" in result


def test_case_insensitive_substring_match(tmp_path):
    src = tmp_path / "in.pdf"
    out = tmp_path / "out.pdf"
    make_pdf(src, ["Contact: john@example.com", "See Johnson report"])

    redact_pdf(str(src), str(out), ["john"])

    result = extract_text(out)
    assert "john" not in result.lower()
    assert "Johnson" not in result
    assert "Contact" in result
    assert "report" in result


def test_multiple_words(tmp_path):
    src = tmp_path / "in.pdf"
    out = tmp_path / "out.pdf"
    make_pdf(src, ["Name: Alice", "SSN: 123-45-6789"])

    redact_pdf(str(src), str(out), ["Alice", "123-45-6789"])

    result = extract_text(out)
    assert "Alice" not in result
    assert "123-45-6789" not in result
    assert "Name" in result
    assert "SSN" in result


def test_word_with_no_match_is_ignored(tmp_path):
    src = tmp_path / "in.pdf"
    out = tmp_path / "out.pdf"
    make_pdf(src, ["Just some text"])

    redact_pdf(str(src), str(out), ["NoSuchWord"])

    result = extract_text(out)
    assert "Just some text" in result


def test_original_file_untouched(tmp_path):
    src = tmp_path / "in.pdf"
    out = tmp_path / "out.pdf"
    make_pdf(src, ["Secret Alice data"])
    original_bytes = src.read_bytes()

    redact_pdf(str(src), str(out), ["Alice"])

    assert src.read_bytes() == original_bytes


def test_cli_reports_missing_input(tmp_path):
    out = tmp_path / "out.pdf"
    result = subprocess.run(
        [sys.executable, str(Path(__file__).resolve().parent.parent / "scripts" / "redact.py"),
         str(tmp_path / "missing.pdf"), str(out), "word"],
        capture_output=True, text=True,
    )
    assert result.returncode != 0
    assert not out.exists()
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `python3 -m pytest pdf_redactor/tests/test_redact.py -v`
Expected: FAIL (collection error) with `ModuleNotFoundError: No module named 'redact'` or similar, since `redact.py` doesn't exist yet.

- [ ] **Step 4: Write the implementation**

Create `pdf_redactor/scripts/redact.py`:

```python
#!/usr/bin/env python3
"""Redact occurrences of given words from a PDF's text content."""

import sys

import fitz  # PyMuPDF


def redact_pdf(input_path: str, output_path: str, words: list[str]) -> None:
    doc = fitz.open(input_path)
    try:
        for page in doc:
            for word in words:
                if not word:
                    continue
                matches = page.search_for(word, quads=False)
                for rect in matches:
                    page.add_redact_annot(rect, fill=(0, 0, 0))
            page.apply_redactions()
        doc.save(output_path)
    finally:
        doc.close()


def main(argv: list[str]) -> int:
    if len(argv) < 4:
        print("Usage: redact.py <input.pdf> <output.pdf> <word> [word ...]", file=sys.stderr)
        return 1

    input_path, output_path, *words = argv[1:]

    try:
        redact_pdf(input_path, output_path, words)
    except Exception as exc:  # noqa: BLE001 - surface any PyMuPDF failure to the caller
        print(f"redact.py: failed to redact {input_path!r}: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
```

Note: `search_for` in PyMuPDF is case-insensitive by default for plain
text search, which satisfies the case-insensitive substring matching
requirement.

- [ ] **Step 5: Run tests to verify they pass**

Run: `python3 -m pytest pdf_redactor/tests/test_redact.py -v`
Expected: all 6 tests PASS

- [ ] **Step 6: Commit**

```bash
git add pdf_redactor/scripts/redact.py pdf_redactor/tests/test_redact.py
git commit -m "Add core PDF redaction logic with tests"
```

---

### Task 2: Orchestration shell script (`redact-personals.sh`)

**Files:**
- Create: `pdf_redactor/scripts/redact-personals.sh`

**Interfaces:**
- Consumes: `redact.py`'s CLI (`python3 redact.py <input> <output> <word...>`, exit 0 on success, non-zero + stderr message on failure) from Task 1.
- Produces: an executable script invoked as `redact-personals.sh file1.pdf file2.pdf ...` (the shape the Quick Action's Run Shell Script action will call it with) that performs the full dialog → persistence → per-file redact loop → error reporting flow described in the spec.

This script isn't unit-testable via pytest (it drives AppleScript dialogs),
so its test step is a documented manual walkthrough using its own
`--words` escape hatch for non-interactive testing, plus one interactive
check.

- [ ] **Step 1: Write the script**

Create `pdf_redactor/scripts/redact-personals.sh`:

```bash
#!/bin/bash
#
# redact-personals.sh
#
# Finder Quick Action entry point for "Redact Personals". Prompts once for
# a comma-separated list of words/strings, then redacts them out of every
# selected PDF, writing "<name>_Red.pdf" next to each original.
#
# Usage: redact-personals.sh file1.pdf file2.pdf ...
# For non-interactive testing, skip the dialog: redact-personals.sh --words "a,b" file1.pdf

set -uo pipefail

# Finder Quick Actions run with a minimal PATH that doesn't include Homebrew
# or user-installed pip scripts.
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/Library/Python/3.9/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULTS_DOMAIN="com.macoshandies.pdfredactor"
PYTHON_BIN="${PDF_REDACTOR_PYTHON:-python3}"

alert() {
  osascript -e "display alert \"Redact Personals\" message \"$1\"" >/dev/null 2>&1
}

words_input=""
if [ "${1:-}" = "--words" ]; then
  words_input="$2"
  shift 2
else
  last_words="$(defaults read "$DEFAULTS_DOMAIN" lastWords 2>/dev/null || echo "")"
  escaped_default=${last_words//\"/\\\"}
  dialog_result=$(osascript <<EOF
try
  set userInput to text returned of (display dialog "Words to redact (comma-separated):" default answer "$escaped_default" with title "Redact Personals")
  return userInput
on error number -128
  return "__CANCELLED__"
end try
EOF
)
  if [ "$dialog_result" = "__CANCELLED__" ]; then
    exit 0
  fi
  words_input="$dialog_result"
  defaults write "$DEFAULTS_DOMAIN" lastWords "$words_input"
fi

# Split on commas, trim whitespace, drop empty entries.
IFS=',' read -ra raw_words <<< "$words_input"
words=()
for w in "${raw_words[@]}"; do
  trimmed=$(echo "$w" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  [ -n "$trimmed" ] && words+=("$trimmed")
done

if [ ${#words[@]} -eq 0 ]; then
  alert "No words entered. Nothing was redacted."
  exit 0
fi

if ! "$PYTHON_BIN" -c "import fitz" >/dev/null 2>&1; then
  alert "PyMuPDF is not installed. Please re-run install.sh for this Quick Action."
  exit 1
fi

for input in "$@"; do
  [ -f "$input" ] || continue

  dir=$(dirname "$input")
  base=$(basename "$input")
  name="${base%.*}"
  output="${dir}/${name}_Red.pdf"

  if ! error_output=$("$PYTHON_BIN" "$SCRIPT_DIR/redact.py" "$input" "$output" "${words[@]}" 2>&1); then
    alert "Failed to redact \"$base\": $error_output"
  fi
done
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x pdf_redactor/scripts/redact-personals.sh`

- [ ] **Step 3: Manual non-interactive test (exercises the redaction loop and error paths without a dialog)**

Run:

```bash
python3 pdf_redactor/tests/test_redact.py 2>/dev/null  # sanity: pytest suite still green
python3 - <<'EOF'
import fitz
doc = fitz.open()
page = doc.new_page()
page.insert_text((72, 72), "Hello Alice Doe", fontsize=12)
doc.save("/tmp/sample.pdf")
EOF

pdf_redactor/scripts/redact-personals.sh --words "Alice" /tmp/sample.pdf
python3 -c "import fitz; print(fitz.open('/tmp/sample_Red.pdf')[0].get_text())"
```

Expected: prints text with "Alice" removed and "Hello" / "Doe" intact;
`/tmp/sample.pdf` is unchanged; `/tmp/sample_Red.pdf` was created.

- [ ] **Step 4: Manual interactive test (dialog + persistence)**

Run: `pdf_redactor/scripts/redact-personals.sh /tmp/sample.pdf`

Expected: a dialog appears pre-filled with "Alice" (from the `defaults
write` in Step 3). Change it to "Doe", click OK. Verify
`/tmp/sample_Red.pdf` is overwritten and now has "Doe" removed instead of
"Alice". Run it again — the dialog should now default to "Doe". Click
Cancel — verify no error and no file changes occur.

- [ ] **Step 5: Commit**

```bash
git add pdf_redactor/scripts/redact-personals.sh
git commit -m "Add orchestration script for Redact Personals Quick Action"
```

---

### Task 3: Automator Quick Action bundle

**Files:**
- Create: `pdf_redactor/Redact Personals.workflow/Contents/Info.plist`
- Create: `pdf_redactor/Redact Personals.workflow/Contents/document.wflow`

**Interfaces:**
- Consumes: `redact-personals.sh` from Task 2, referenced by the path it will live at post-install: `$HOME/Library/Services/Redact Personals.workflow/Contents/Resources/redact-personals.sh`.
- Produces: a workflow bundle that, once copied into `~/Library/Services`, adds a "Redact Personals" item to Finder's right-click menu that is visible only for files of UTI `com.adobe.pdf`.

This bundle has no automated test (it's inert until installed); verification is manual, after Task 4's `install.sh` exists.

- [ ] **Step 1: Create `Info.plist`**

Create `pdf_redactor/Redact Personals.workflow/Contents/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSBackgroundColorName</key>
			<string>background</string>
			<key>NSIconName</key>
			<string>NSActionTemplate</string>
			<key>NSMenuItem</key>
			<dict>
				<key>default</key>
				<string>Redact Personals</string>
			</dict>
			<key>NSMessage</key>
			<string>runWorkflowAsService</string>
			<key>NSRequiredContext</key>
			<dict>
				<key>NSApplicationIdentifier</key>
				<string>com.apple.finder</string>
			</dict>
			<key>NSSendFileTypes</key>
			<array>
				<string>com.adobe.pdf</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
```

- [ ] **Step 2: Create `document.wflow`**

Create `pdf_redactor/Redact Personals.workflow/Contents/document.wflow`
(same shape as `image-compressor`'s, but calling the new script):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AMApplicationBuild</key>
	<string>528</string>
	<key>AMApplicationVersion</key>
	<string>2.10</string>
	<key>AMDocumentVersion</key>
	<string>2</string>
	<key>actions</key>
	<array>
		<dict>
			<key>action</key>
			<dict>
				<key>AMAccepts</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Optional</key>
					<true/>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.string</string>
					</array>
				</dict>
				<key>AMActionVersion</key>
				<string>2.0.3</string>
				<key>AMApplication</key>
				<array>
					<string>Automator</string>
				</array>
				<key>AMParameterProperties</key>
				<dict>
					<key>COMMAND_STRING</key>
					<dict/>
					<key>CheckedForUserDefaultShell</key>
					<dict/>
					<key>inputMethod</key>
					<dict/>
					<key>shell</key>
					<dict/>
					<key>source</key>
					<dict/>
				</dict>
				<key>AMProvides</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.string</string>
					</array>
				</dict>
				<key>ActionBundlePath</key>
				<string>/System/Library/Automator/Run Shell Script.action</string>
				<key>ActionName</key>
				<string>Run Shell Script</string>
				<key>ActionParameters</key>
				<dict>
					<key>COMMAND_STRING</key>
					<string>"$HOME/Library/Services/Redact Personals.workflow/Contents/Resources/redact-personals.sh" "$@"</string>
					<key>CheckedForUserDefaultShell</key>
					<true/>
					<key>inputMethod</key>
					<integer>1</integer>
					<key>shell</key>
					<string>/bin/bash</string>
					<key>source</key>
					<string></string>
				</dict>
				<key>BundleIdentifier</key>
				<string>com.apple.RunShellScript</string>
				<key>CFBundleVersion</key>
				<string>2.0.3</string>
				<key>CanShowSelectedItemsWhenRun</key>
				<false/>
				<key>CanShowWhenRun</key>
				<true/>
				<key>Category</key>
				<array>
					<string>AMCategoryUtilities</string>
				</array>
				<key>Class Name</key>
				<string>RunShellScriptAction</string>
				<key>InputUUID</key>
				<string>1B7480B9-A4EB-486A-B6A8-75A633E1F5C7</string>
				<key>Keywords</key>
				<array>
					<string>Shell</string>
					<string>Script</string>
					<string>Command</string>
					<string>Run</string>
					<string>Unix</string>
				</array>
				<key>OutputUUID</key>
				<string>27D681F0-CDD6-4460-AB46-EF3F598E31DA</string>
				<key>ShowWhenRun</key>
				<false/>
				<key>UUID</key>
				<string>42A4C0A2-9B81-4D49-A231-B67FC7827DCE</string>
				<key>UnlocalizedApplications</key>
				<array>
					<string>Automator</string>
				</array>
				<key>arguments</key>
				<dict>
					<key>0</key>
					<dict>
						<key>default value</key>
						<integer>0</integer>
						<key>name</key>
						<string>inputMethod</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>0</string>
					</dict>
					<key>1</key>
					<dict>
						<key>default value</key>
						<false/>
						<key>name</key>
						<string>CheckedForUserDefaultShell</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>1</string>
					</dict>
					<key>2</key>
					<dict>
						<key>default value</key>
						<string></string>
						<key>name</key>
						<string>source</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>2</string>
					</dict>
					<key>3</key>
					<dict>
						<key>default value</key>
						<string></string>
						<key>name</key>
						<string>COMMAND_STRING</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>3</string>
					</dict>
					<key>4</key>
					<dict>
						<key>default value</key>
						<string>/bin/sh</string>
						<key>name</key>
						<string>shell</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>4</string>
					</dict>
				</dict>
				<key>isViewVisible</key>
				<integer>1</integer>
				<key>location</key>
				<string>309.000000:361.000000</string>
				<key>nibPath</key>
				<string>/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib</string>
			</dict>
			<key>isViewVisible</key>
			<integer>1</integer>
		</dict>
	</array>
	<key>connectors</key>
	<dict/>
	<key>workflowMetaData</key>
	<dict>
		<key>applicationBundleID</key>
		<string>com.apple.finder</string>
		<key>applicationBundleIDsByPath</key>
		<dict>
			<key>/System/Library/CoreServices/Finder.app</key>
			<string>com.apple.finder</string>
		</dict>
		<key>applicationPath</key>
		<string>/System/Library/CoreServices/Finder.app</string>
		<key>applicationPaths</key>
		<array>
			<string>/System/Library/CoreServices/Finder.app</string>
		</array>
		<key>inputTypeIdentifier</key>
		<string>com.apple.Automator.fileSystemObject</string>
		<key>outputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>presentationMode</key>
		<integer>15</integer>
		<key>processesInput</key>
		<false/>
		<key>serviceApplicationBundleID</key>
		<string>com.apple.finder</string>
		<key>serviceApplicationPath</key>
		<string>/System/Library/CoreServices/Finder.app</string>
		<key>serviceInputTypeIdentifier</key>
		<string>com.apple.Automator.fileSystemObject</string>
		<key>serviceOutputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>serviceProcessesInput</key>
		<false/>
		<key>systemImageName</key>
		<string>NSActionTemplate</string>
		<key>useAutomaticInputType</key>
		<false/>
		<key>workflowTypeIdentifier</key>
		<string>com.apple.Automator.servicesMenu</string>
	</dict>
</dict>
</plist>
```

- [ ] **Step 3: Validate both plists are well-formed**

Run:
```bash
plutil -lint "pdf_redactor/Redact Personals.workflow/Contents/Info.plist"
plutil -lint "pdf_redactor/Redact Personals.workflow/Contents/document.wflow"
```
Expected: both print `OK`.

- [ ] **Step 4: Commit**

```bash
git add "pdf_redactor/Redact Personals.workflow"
git commit -m "Add Redact Personals Automator Quick Action bundle"
```

---

### Task 4: Install/uninstall scripts, READMEs, and end-to-end verification

**Files:**
- Create: `pdf_redactor/install.sh`
- Create: `pdf_redactor/uninstall.sh`
- Create: `pdf_redactor/README.md`
- Modify: `README.md:5-8` (repo root — add `pdf_redactor` to the utilities list)

**Interfaces:**
- Consumes: the workflow bundle from Task 3 (`pdf_redactor/Redact Personals.workflow`), and the scripts from Tasks 1-2 (`pdf_redactor/scripts/redact.py`, `pdf_redactor/scripts/redact-personals.sh`).
- Produces: a working, installable Quick Action a user can right-click a PDF to invoke, matching `image-compressor`'s install/uninstall UX.

- [ ] **Step 1: Write `install.sh`**

Create `pdf_redactor/install.sh`:

```bash
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
```

- [ ] **Step 2: Write `uninstall.sh`**

Create `pdf_redactor/uninstall.sh`:

```bash
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
```

- [ ] **Step 3: Make both scripts executable**

Run: `chmod +x pdf_redactor/install.sh pdf_redactor/uninstall.sh`

- [ ] **Step 4: Write `pdf_redactor/README.md`**

Create `pdf_redactor/README.md`:

```markdown
# pdf-redactor

A Finder Quick Action, "Redact Personals", that permanently redacts
user-specified words/strings out of a PDF's text content.

## Install

```bash
./install.sh
```

This installs [PyMuPDF](https://pymupdf.readthedocs.io/) via pip and
copies the Quick Action into `~/Library/Services`.

## Usage

1. Right-click one or more `.pdf` files in Finder.
2. Choose Quick Actions > Redact Personals.
3. Enter a comma-separated list of words/strings to redact (the field
   remembers what you typed last time) and click OK.
4. A redacted copy of each selected PDF is created alongside the
   original, named `<name>_Red.pdf`. The original file is never modified.

Matching is case-insensitive and matches substrings (e.g. "john" also
redacts "John" and "Johnson"). Words with no matches in a given PDF are
silently skipped. Re-running overwrites any existing `_Red.pdf`.

Redaction only removes text that exists as extractable text in the PDF —
text baked into a scanned image is not affected.

## Uninstall

```bash
./uninstall.sh
```
```

- [ ] **Step 5: Update the repo root README**

Read `README.md` first, then add a bullet after the `image-compressor`
entry:

```markdown
- [`pdf_redactor`](pdf_redactor/) - Finder Quick Action to redact
  specified words from a PDF's text.
```

- [ ] **Step 6: Run the full automated test suite one more time**

Run: `python3 -m pytest pdf_redactor/tests/test_redact.py -v`
Expected: all tests PASS.

- [ ] **Step 7: End-to-end manual verification**

```bash
./pdf_redactor/install.sh
```

Then in Finder:
- Create or use a real PDF containing some placeholder personal info (e.g. a name and an email).
- Right-click it — confirm "Redact Personals" appears under Quick Actions, and confirm it does *not* appear on a non-PDF file (e.g. a `.txt` or `.jpg`).
- Run it, enter the placeholder name/email comma-separated, click OK.
- Confirm a `<name>_Red.pdf` appears next to the original, that opening it shows a black box where the text was, that selecting/copying text in that area yields nothing, and that the original PDF is unchanged.
- Run it again on the same file — confirm the dialog pre-fills the previous input, and that re-confirming overwrites `_Red.pdf` without error.

- [ ] **Step 8: Commit**

```bash
git add pdf_redactor/install.sh pdf_redactor/uninstall.sh pdf_redactor/README.md README.md
git commit -m "Add install/uninstall scripts and docs for Redact Personals"
```

---

## Self-Review Notes

- Spec coverage: Finder restriction to PDFs (Task 3), single dialog with persisted default (Task 2), comma-splitting/trimming (Task 2), case-insensitive substring redaction (Task 1), `_Red.pdf` naming + overwrite + original untouched (Task 1 tests + Task 2), silently ignoring no-match words (Task 1 test), empty-input abort and missing-PyMuPDF abort (Task 2), per-file failure alert without stopping the batch (Task 2), pip-based install (Task 4), README/uninstall (Task 4) — all covered.
- No placeholders: every step has literal file contents or exact commands.
- Type/name consistency checked: `redact_pdf(input_path, output_path, words)` used identically in Task 1's implementation and tests; `redact.py`'s CLI signature (`<input> <output> <word...>`) matches how Task 2's script invokes it; the workflow's shell command path in Task 3 matches where Task 4's `install.sh` copies `redact-personals.sh` to.
