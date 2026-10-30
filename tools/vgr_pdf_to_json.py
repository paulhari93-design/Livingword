"""Read an English sermon PDF from Voice Of God Recordings (download_vgr_text.bat) into
the app's format, word for word (VGR asked that the text is not changed).

A VGR PDF looks like:
    page 1:   THE TITLE
              …first paragraph (no number printed)…
              2 Second paragraph…
                  An indented line starts a new block inside the same paragraph.
    page 2+:  "2 THE SPOKEN WORD" / "THE TITLE 3"   (running header with page number)
    last two: an information page (code, title, place, ©) and a copyright notice.

Returns (code, title, paragraphs, heading), like messagehub_to_json.parse_messagehub.
"""
import re
import sys
from pathlib import Path

import pypdfium2 as pdfium

CODE_RE = re.compile(r"^(\d{2}-\d{4}[A-Za-z]?)")
PUA_RE = re.compile(r"[-]")  # decorative glyphs (drop caps)


def _lines(page):
    """[(text, x_left, y_bottom)] for one page, in reading order."""
    tp = page.get_textpage()
    n = tp.count_chars()
    if n <= 0:
        return []
    text = tp.get_text_range(0, n)
    out = []
    i = 0
    for raw in re.split(r"(\r\n|\n)", text):
        if raw in ("\r\n", "\n"):
            i += len(raw)
            continue
        # \ufffe / \u00ad: a word split over two lines with a hyphen ("forty-" "seven").
        line = PUA_RE.sub("", raw).replace("\ufffe", "-").replace("\u00ad", "-").strip()
        if line:
            # Position of the first real character of the line.
            k = i + (len(raw) - len(raw.lstrip()))
            while k < i + len(raw) and PUA_RE.match(raw[k - i]):
                k += 1
            try:
                left = tp.get_charbox(min(k, n - 1), loose=True)[0]
                # Height from a character in the middle of the line (the paragraph
                # number at the start is printed in another font).
                mid = min(i + len(raw) // 2, n - 1)
                bottom = tp.get_charbox(mid, loose=True)[1]
            except Exception:
                left, bottom = 0.0, 0.0
            out.append((line, left, bottom))
        i += len(raw)
    return out


def _is_header(line, page_no):
    """Running header, e.g. '2 THE SPOKEN WORD' or 'THE RAPTURE 3'."""
    t = line.strip()
    letters = re.sub(r"[^A-Za-z]", "", t)
    if not letters or letters.upper() != letters:
        return False
    return bool(re.match(r"^\d+\s", t) or re.search(r"\s\d+$", t)) or page_no == 0


def _join(a, b):
    """Joins two lines of one paragraph. After a dash or "…" VGR has no space
    ("cast out—" + "cast out devils"), otherwise one space."""
    if not a:
        return b
    if a.endswith(("—", "…", "-")):
        return a + b
    return a + " " + b


def parse_vgr_pdf(path):
    src = Path(path)
    m = CODE_RE.match(src.stem)
    if not m:
        print(f"SKIPPED {src.name}: no code in the file name.")
        return None
    code = m.group(1).upper()
    file_title = src.stem[len(m.group(1)):].strip() or code

    try:
        doc = pdfium.PdfDocument(str(src))
    except Exception as e:
        print(f"SKIPPED {src.name}: cannot open ({e}).")
        return None

    pages = [_lines(p) for p in doc]
    doc.close()

    # The information page (code + title, place) and the copyright notice at the end.
    place = []
    end = len(pages)
    for k in range(len(pages) - 1, max(-1, len(pages) - 4), -1):
        texts = [t for t, _x, _y in pages[k]]
        joined = " ".join(texts)
        if "Copyright Notice" in joined or "ALL RIGHTS RESERVED" in joined.upper() and k >= len(pages) - 3:
            end = k
            if texts and texts[0].upper().startswith(code):
                # "65-1204 The Rapture" / "Ramada Inn" / "Yuma, Arizona U.S.A." / "ENGLISH" / "©…"
                for t in texts[1:]:
                    if t.upper() in ("ENGLISH",) or t.startswith("©") or "VOICE OF GOD" in t.upper():
                        break
                    place.append(t)
    pages = pages[:end]

    paragraphs = []  # [text]
    expected = 2     # paragraph 1 has no printed number
    current = ""

    def flush():
        nonlocal current
        if current.strip():
            num = re.match(r"^(\d+)  (.*)$", current, re.S)
            if num:
                paragraphs.append(num.group(1) + "  " + " ".join(num.group(2).split()))
            else:
                paragraphs.append(" ".join(current.split()))
        current = ""

    # Normal distance between two lines; a clearly bigger space starts a new block.
    gaps = sorted(a[2] - b[2] for pg in pages for a, b in zip(pg, pg[1:]) if 5 < a[2] - b[2] < 30)
    line_gap = gaps[len(gaps) // 2] if gaps else 12.0

    # Paragraph numbers usually start at 2 (1 is not printed), but a sermon in several
    # parts (e.g. Hebrews) goes on from the last part: find where the numbering starts.
    starts = []
    for pno, pg in enumerate(pages):
        if not pg:
            continue
        margin = min(x for _t, x, _y in pg)
        for text, x, _y in pg:
            m2 = re.match(r"^(\d+)\s+\S", text)
            if m2 and x - margin < 6:
                starts.append(int(m2.group(1)))
    for k, c in enumerate(starts):
        later = set(starts[k + 1:k + 12])
        if sum(1 for d in range(1, 6) if c + d in later) >= 4:
            expected = c
            break
    first_number = expected - 1

    prev_indent = 0.0
    for pno, pg in enumerate(pages):
        body = list(pg)
        # Drop the title (page 1) / running header (other pages).
        if pno == 0:
            while body and _is_header(body[0][0], 0):
                body.pop(0)
        elif body and _is_header(body[0][0], pno):
            body.pop(0)
        if not body:
            continue
        margin = min(x for _t, x, _y in body)
        prev_y = None
        for li, (text, x, y) in enumerate(body):
            indent = x - margin
            spaced = prev_y is not None and (prev_y - y) > line_gap * 1.42 and indent > 6
            prev_y = y
            num = re.match(r"^(\d+)\s+(.*)$", text)
            if num and int(num.group(1)) == expected and indent < 6:
                flush()
                current = f"{expected}  {num.group(2)}"
                expected += 1
            elif spaced or (indent > prev_indent + 4 and not (pno == 0 and li < 4 and not paragraphs)) or not current:
                # A line that starts further right than the one above starts a new block
                # (VGR's indented sub-paragraphs and Bible verses). On page 1 the big first
                # letter pushes the first lines to the right: not a new block.
                flush()
                current = text
            else:
                current = _join(current, text)
            prev_indent = indent
        # A paragraph may continue on the next page: don't flush here.
    flush()

    if not paragraphs:
        print(f"SKIPPED {src.name}: no text found.")
        return None
    if not re.match(r"^\d+\s\s", paragraphs[0]):
        paragraphs[0] = f"{first_number}  " + paragraphs[0]

    heading = [{"k": "title", "t": file_title}, {"k": "info", "t": code}]
    if place:
        heading.append({"k": "info", "t": ", ".join(place)})
    return code, file_title, paragraphs, heading


if __name__ == "__main__":
    for a in sys.argv[1:]:
        r = parse_vgr_pdf(a)
        if r:
            code, title, paras, heading = r
            print(code, "|", title, "|", heading[-1]["t"], "|", len(paras), "paragraphs")
            for x in paras[:6] + ["..."] + paras[-3:]:
                print("   ", x[:150])
