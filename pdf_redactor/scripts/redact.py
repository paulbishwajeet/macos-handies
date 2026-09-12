#!/usr/bin/env python3
"""Redact occurrences of given words from a PDF's text content."""

import sys

import pymupdf as fitz  # PyMuPDF


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

        # Clear document metadata (title/author/subject/keywords, etc.) so
        # redacted words don't survive verbatim in the metadata dictionary.
        doc.set_metadata({})
        # Also strip XMP/XML metadata streams, if present, on PyMuPDF
        # versions that expose this API.
        if hasattr(doc, "del_xml_metadata"):
            doc.del_xml_metadata()

        # garbage=4 + clean=True drops unreferenced/old objects (including
        # stale content streams left behind by incrementally-updated source
        # PDFs) so redacted text can't survive in the raw output bytes.
        doc.save(output_path, garbage=4, clean=True, deflate=True)
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
