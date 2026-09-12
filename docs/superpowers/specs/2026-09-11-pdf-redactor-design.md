# PDF Redactor — Finder Quick Action

## Purpose

Add a "Redact Personals" item to the Finder right-click menu that only
appears for `.pdf` files. Clicking it prompts for a comma-separated list of
words/strings and produces a redacted copy of the PDF with those strings
permanently removed (not just visually covered).

## Folder layout

New top-level folder `pdf_redactor/`, mirroring the existing
`image-compressor/` folder:

```
pdf_redactor/
  Redact Personals.workflow/
    Contents/
      Info.plist
      document.wflow
  scripts/
    redact-personals.sh
    redact.py
  install.sh
  uninstall.sh
  README.md
```

## Finder integration

`Info.plist` declares an `NSServices` entry restricted to PDFs via
`NSSendFileTypes: com.adobe.pdf` (the same mechanism the image compressor
uses with `public.jpeg` / `public.png`), so the menu item is invisible for
any non-PDF file. The workflow's single action is "Run Shell Script",
invoking `redact-personals.sh` with the selected file paths as arguments —
same shape as the image compressor's `document.wflow`.

## User flow

1. User selects one or more PDFs in Finder, right-clicks, chooses
   Quick Actions → "Redact Personals".
2. `redact-personals.sh` runs **once** regardless of how many files were
   selected. It shows a single AppleScript dialog
   (`display dialog ... default answer <last value>`) with a text field
   pre-filled with the last-used comma-separated string, read via
   `defaults read com.macoshandies.pdfredactor lastWords` (empty string if
   unset).
3. User edits the string if needed and clicks OK, or clicks Cancel to abort
   with no files touched.
4. On OK, the script saves the string back via
   `defaults write com.macoshandies.pdfredactor lastWords "<value>"` so the
   next run pre-fills it.
5. The script splits the string on commas, trims whitespace from each
   piece, and drops empty entries.
6. For each selected PDF, the script calls
   `redact.py <input.pdf> <output.pdf> <word1> <word2> ...`.
7. `redact.py` (using PyMuPDF / `fitz`):
   - Opens the input PDF.
   - For each page, for each word, does a case-insensitive `search_for`
     to find all matching text rectangles (substring match — e.g. "john"
     also matches "John" and "Johnson").
   - Adds a redaction annotation over every match found.
   - Calls `apply_redactions()` per page, which removes the underlying
     text content (not just an overlay) and paints a black box over each
     redacted area.
   - Saves the result to `<name>_Red.pdf` in the same directory as the
     original, **overwriting** any existing file of that name.
   - The original file is never modified.
8. Words with no matches anywhere in the document are silently ignored —
   no error, no partial failure.

## Dependencies / install

- `install.sh`:
  - Runs `pip3 install --user pymupdf` (no Homebrew formula needed for
    this; PyMuPDF is Python-only).
  - Copies `Redact Personals.workflow` into `~/Library/Services`.
  - Copies `redact-personals.sh` and `redact.py` into the workflow
    bundle's `Contents/Resources`, marking the shell script executable.
  - Prints where to find the new Quick Action, matching the tone of
    `image-compressor/install.sh`.
- `uninstall.sh`: removes the workflow from `~/Library/Services` (mirrors
  the image compressor's uninstall script; does not remove the `pymupdf`
  pip package or clear the saved `defaults` string).

## Error handling

- If `redact.py` can't import `fitz` (PyMuPDF missing/broken install),
  `redact-personals.sh` shows an `osascript` alert telling the user to
  re-run `install.sh`, and aborts without processing any file.
- If the comma-separated input is empty (or only whitespace/commas) after
  trimming, the script shows an alert ("No words entered") and aborts
  without creating any `_Red` copies.
- If an individual PDF fails to process (corrupt file, permissions, etc.),
  the script reports the error for that file via `osascript` but continues
  processing the remaining selected files.

## Out of scope

- OCR / redacting text that only exists inside scanned page images (the
  PDF's text layer must contain the target strings as extractable text).
- Manual page-region / coordinate-based redaction.
- Redacting anything other than text (e.g. embedded images, metadata,
  annotations) beyond what `apply_redactions()` covers by default.

## Testing plan

- Manual: create a sample PDF with known text (via `python3` + `reportlab`
  or an existing test fixture), install the Quick Action, run it via
  Finder against single and multi-file selections, and verify:
  - the menu item shows only for `.pdf` files;
  - the dialog pre-fills the previous value on a second run;
  - matched words are gone from `_Red.pdf`'s extracted text
    (`fitz`/`pdftotext`) and a black box appears at each location;
  - the original PDF is untouched;
  - re-running overwrites the existing `_Red.pdf`;
  - a word with no matches doesn't cause an error;
  - Cancel produces no output files.
