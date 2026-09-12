import subprocess
import sys
from pathlib import Path

import pymupdf as fitz
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


def test_metadata_is_scrubbed(tmp_path):
    src = tmp_path / "in.pdf"
    out = tmp_path / "out.pdf"
    make_pdf(src, ["Hello Alice"])

    doc = fitz.open(str(src))
    doc.set_metadata({
        "title": "Report about Alice",
        "author": "Alice Smith",
        "subject": "Alice's records",
        "keywords": "Alice, confidential",
    })
    doc.saveIncr()
    doc.close()

    redact_pdf(str(src), str(out), ["Alice"])

    result_doc = fitz.open(str(out))
    metadata = result_doc.metadata
    result_doc.close()

    metadata_values = " ".join(str(v) for v in metadata.values() if v)
    assert "Alice" not in metadata_values


def test_cli_reports_missing_input(tmp_path):
    out = tmp_path / "out.pdf"
    result = subprocess.run(
        [sys.executable, str(Path(__file__).resolve().parent.parent / "scripts" / "redact.py"),
         str(tmp_path / "missing.pdf"), str(out), "word"],
        capture_output=True, text=True,
    )
    assert result.returncode != 0
    assert not out.exists()
