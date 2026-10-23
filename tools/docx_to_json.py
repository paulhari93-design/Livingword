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
from docx.enum.text import WD_ALIGN_PARAGRAPH

ASSETS = Path(__file__).resolve().parent.parent / "assets" / "messages"


CODE_RE = re.compile(r"^(\d{2}-\d{4}[A-Za-z]?)\s*[-_ ]*\s*(.*)$")


TAMIL_START = re.compile(r"^(\d{1,4})(?=[\u0B80-\u0BFF])")  # "2நீண்ட" -> "2  நீண்ட"
NOISE = re.compile(r"printed\s+in", re.IGNORECASE)              # "Tamil - Printed In Aug 2026"


def _is_centered(p):
    al = p.alignment if p.alignment is not None else p.style.paragraph_format.alignment
    return al == WD_ALIGN_PARAGRAPH.CENTER


def _size(p):
    sizes = [r.font.size.pt for r in p.runs if r.text.strip() and r.font.size]
    return max(sizes) if sizes else 0


def _bold(p):
    return any(r.bold for r in p.runs if r.text.strip()) or bool(p.style.font.bold)


def parse_docx(docx_path):
    """Returns (code, title, paragraphs, heading) for a Word file, or None if it can't be used.

    heading = [{"k": "title"|"info", "t": text}, ...]  - the centred lines at the top
              (title in bold; date / code / place shown centred under it).
    paragraphs = the body text after the heading.
    """
    src = Path(docx_path)
    doc = Document(str(src))
    paras = [p for p in doc.paragraphs if p.text.strip()]
    if not paras:
        print(f"SKIPPED {src.name}: no text found.")
        return None

    # Code + title for the book list: from the file name, else from the first line.
    m = CODE_RE.match(src.stem) or CODE_RE.match(paras[0].text.strip())
    if not m:
        print(f"SKIPPED {src.name}: no code found. Start the file name or the "
              f"first line with a code like 47-0508.")
        return None
    code, title = m.group(1), (m.group(2).strip() or m.group(1))

    # The heading = the centred lines before the first normal paragraph.
    head_paras = []
    for p in paras:
        if _is_centered(p) and len(head_paras) < 8:
            head_paras.append(p)
        else:
            break
    body_paras = paras[len(head_paras):]

    heading = []
    title_done = False
    title_fmt = None
    for p in head_paras:
        text = p.text.strip()
        if NOISE.search(text):
            continue
        # "51-0721 Title" -> "Title"; a line that is only the code stays as info.
        cm = CODE_RE.match(text)
        if cm and cm.group(2).strip() and cm.group(1).upper() == code.upper():
            text = cm.group(2).strip().lstrip("–-— ").strip()
        if not title_done:
            if title_fmt is None and not CODE_RE.match(text) and not text.startswith("("):
                title_fmt = (_size(p), _bold(p))
                heading.append({"k": "title", "t": text})
                continue
            if title_fmt is not None and (_size(p), _bold(p)) == title_fmt \
                    and not text.startswith("(") and not CODE_RE.match(text):
                heading.append({"k": "title", "t": text})  # title continues on a 2nd line
                continue
            title_done = title_fmt is not None
        heading.append({"k": "info", "t": text})

    # If the heading title is the file-name title written without spaces
    # (e.g. "மெய்யானதிராட்சைசெடியும்,கள்ளதிராட்சைசெடியும்"), use the file name's spacing.
    def squash(t):
        return re.sub(r"[\s,.\-–—]", "", t)
    titles = [h["t"] for h in heading if h["k"] == "title"]
    if titles and squash(" ".join(titles)) == squash(title) and title.count(" ") > " ".join(titles).count(" "):
        first = next(i for i, h in enumerate(heading) if h["k"] == "title")
        heading = [h for h in heading if h["k"] != "title"]
        heading.insert(first, {"k": "title", "t": title})

    paragraphs = [TAMIL_START.sub(r"\1  ", p.text.strip()) for p in body_paras]
    return code, title, paragraphs, heading


def convert(docx_path: str) -> None:
    parsed = parse_docx(docx_path)
    if parsed is None:
        return
    code, title, paragraphs, heading = parsed

    ASSETS.mkdir(parents=True, exist_ok=True)
    out_file = f"{code}.json"
    (ASSETS / out_file).write_text(
        json.dumps({"code": code, "title": title, "heading": heading, "paragraphs": paragraphs},
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
