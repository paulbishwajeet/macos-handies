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

## Distributing to others

If you want to share this Quick Action with someone who doesn't have
this repo, Python, or PyMuPDF, you can build a self-contained,
double-clickable `.pkg` installer instead of having them clone this
repo and run `install.sh`. See `packaging/README.md` for build and
distribution instructions.
