"""Convert a translated message (.docx) into the app's format.

Usage (run from the livingword project folder):
    pip install python-docx
    python tools/docx_to_json.py "C:\\path\\to\\47-0508 Message Title.docx"

The file name must start with the code, e.g. "47-0508 Title.docx".
It writes assets/messages/<code>.json and adds/updates the entry in
assets/messages/index.json. Rebuild the app to see it.
"""
import json
import re
import sys
from pathlib import Path

from docx import Document

ASSETS = Path(__file__).resolve().parent.parent / "assets" / "messages"


CODE_RE = re.compile(r"^(\d{2}-\d{4}[A-Za-z]?)\s*[-_ ]*\s*(.*)$")


def convert(docx_path: str) -> None:
    src = Path(docx_path)
    doc = Document(str(src))
    paragraphs = [p.text.strip() for p in doc.paragraphs if p.text.strip()]
    if not paragraphs:
        print(f"SKIPPED {src.name}: no text found.")
        return

    # Code + title: from the file name, or else from the first line of the document.
    m = CODE_RE.match(src.stem)
    if m:
        code, title = m.group(1), (m.group(2).strip() or m.group(1))
        first = CODE_RE.match(paragraphs[0])
        if first and first.group(1) == code:
            paragraphs = paragraphs[1:]  # don't repeat the heading line
    else:
        first = CODE_RE.match(paragraphs[0])
        if not first:
            print(f"SKIPPED {src.name}: no code found. Start the file name or the "
                  f"first line with a code like 47-0508.")
            return
        code, title = first.group(1), (first.group(2).strip() or first.group(1))
        paragraphs = paragraphs[1:]

    # Paragraph numbers like "2நீண்ட..." -> "2  நீண்ட..."
    paragraphs = [re.sub(r"^(\d{1,4})(?=\D)\s*", r"\1  ", p) for p in paragraphs]

    ASSETS.mkdir(parents=True, exist_ok=True)
    out_file = f"{code}.json"
    (ASSETS / out_file).write_text(
        json.dumps({"code": code, "title": title, "paragraphs": paragraphs},
                   ensure_ascii=False, indent=1),
        encoding="utf-8",
    )

    index_path = ASSETS / "index.json"
    index = json.loads(index_path.read_text(encoding="utf-8")) if index_path.exists() else []
    index = [e for e in index if e["code"] != code]
    index.append({"code": code, "title": title, "file": out_file})
    index.sort(key=lambda e: e["code"])
    index_path.write_text(json.dumps(index, ensure_ascii=False, indent=1), encoding="utf-8")

    print(f"OK: {code} '{title}' - {len(paragraphs)} paragraphs -> assets/messages/{out_file}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    for path in sys.argv[1:]:
        convert(path)
