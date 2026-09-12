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
