"""Read a Tamil sermon PDF from Voice Of God Recordings (download_vgr_tamil_text.bat)
into the app's format, word for word.

Two things make VGR's Tamil PDFs hard to read as text, and both are repaired here:

1. Joined letters such as "ன்", "கு", "ரு" are single shapes in the font (Lohit Tamil),
   and many PDFs don't say which letters those shapes are: reading them gives
   "æ", "Ý", "ä" … instead of Tamil. Each shape is recognised by its outline and
   replaced by the right letters (table: vgr_tamil_glyphs.json, made from the PDFs).
2. The PDF stores "ெ ே ை" before the letter, the way they are printed ("ேக" for "கே").
   They are put back in the right order ("கே", "கொ", "கோ").

Returns (code, title, paragraphs, heading), like vgr_pdf_to_json.parse_vgr_pdf.
"""
import csv
import ctypes
import hashlib
import io
import json
import re
import sys
from pathlib import Path

import pypdfium2 as pdfium
import pypdfium2.raw as pdfium_c
from fontTools.ttLib import TTFont
from pypdf import PdfReader

CODE_RE = re.compile(r"^(\d{2}-\d{4}[A-Za-z]?)")
PUA_RE = re.compile(r"[-]")
_HERE = Path(__file__).resolve().parent
_GLYPHS = None  # style -> outline hash -> text
_ALL_GLYPHS = None


def _glyph_table():
    global _GLYPHS, _ALL_GLYPHS
    if _GLYPHS is None:
        _GLYPHS = json.loads((_HERE / "vgr_tamil_glyphs.json").read_text(encoding="utf-8"))
        _ALL_GLYPHS = {}
        for st, d in _GLYPHS.items():
            if st.startswith("_"):
                continue
            for h, t in d.items():
                _ALL_GLYPHS.setdefault(h, t)
    return _GLYPHS, _ALL_GLYPHS


_STD = None


def _standard():
    """Lohit Tamil's usual shape number -> letters."""
    global _STD
    if _STD is None:
        styles, _all = _glyph_table()
        _STD = {int(k): v for k, v in styles.get("_std", {}).items()}
        # Letters not seen in the PDFs' own lists, in Lohit Tamil's order.
        extra = {5: '"', 6: "#", 7: "$", 8: "%", 9: "&", 10: "'", 13: "*", 14: "+", 18: "/",
                 31: "<", 32: "=", 33: ">", 35: "@", 37: "\\", 84: "ஶ", 90: "ீ",
                 96: "ொ", 97: "ோ", 98: "ௌ"}
        for k, v in extra.items():
            _STD.setdefault(k, v)
    return _STD


def _ok(s):
    """True when the PDF's own text for a shape is real Tamil / ordinary characters."""
    return bool(s) and all(
        0x0B80 <= ord(ch) <= 0x0BFF or 0x20 <= ord(ch) < 0x7F or ch in "’“”‘…—–‑®©"
        for ch in s)


def _tounicode(data):
    m = {}
    s = data.decode("latin-1")
    for blk in re.findall(r"beginbfchar(.*?)endbfchar", s, re.S):
        for a, b in re.findall(r"<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>", blk):
            m[int(a, 16)] = bytes.fromhex(b).decode("utf-16-be", "replace")
    for blk in re.findall(r"beginbfrange(.*?)endbfrange", s, re.S):
        for a, b, c in re.findall(r"<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>", blk):
            a, b = int(a, 16), int(b, 16)
            base = bytes.fromhex(c).decode("utf-16-be", "replace")
            if base:
                for i in range(a, b + 1):
                    try:
                        m[i] = base[:-1] + chr(ord(base[-1]) + i - a)
                    except ValueError:
                        pass
    return m


def _outline(font, gid):
    order = font.getGlyphOrder()
    if gid >= len(order):
        return None
    g = font["glyf"][order[gid]]
    if not g.numberOfContours:
        return None
    if g.isComposite():
        return "comp:" + ",".join(c.glyphName for c in g.components)
    return hashlib.md5(repr((list(g.coordinates), list(g.endPtsOfContours))).encode()).hexdigest()


def _font_maps(path):
    """{full font name: {character the PDF gives: right Tamil text}} for the Lohit fonts."""
    styles, everything = _glyph_table()
    maps = {}
    reader = PdfReader(str(path))
    for page in reader.pages:
        res = page.get("/Resources")
        fonts = res.get_object().get("/Font") if res else None
        if not fonts:
            continue
        for _k, f in fonts.get_object().items():
            f = f.get_object()
            name = str(f.get("/BaseFont", "")).lstrip("/")
            if name in maps or "/DescendantFonts" not in f:
                continue
            fd = f["/DescendantFonts"][0].get_object()["/FontDescriptor"].get_object()
            if "Excelsior" in name and "/ToUnicode" not in f:
                # Paragraph numbers in a font without a letter list: shapes 13..22 are 0..9.
                for n in (name, str(fd.get("/FontName", "")).lstrip("/")):
                    maps[n] = {chr(13 + d): str(d) for d in range(10)}
                continue
            if "Lohit" not in name:
                continue
            # The text reader names a font by its descriptor ("AAGBPD+LohitTamil"),
            # sometimes by the base name: keep the map under both.
            names = {name, str(fd.get("/FontName", "")).lstrip("/")}
            if "/FontFile2" not in fd:
                if "/ToUnicode" not in f:
                    # Converted font without any letter list: the shapes keep Lohit Tamil's
                    # usual numbers, so the standard table tells the letters.
                    std_map = {chr(g): t for g, t in _standard().items() if chr(g) != t}
                    for n in names:
                        maps[n] = std_map
                continue
            try:
                font = TTFont(io.BytesIO(fd["/FontFile2"].get_object().get_data()))
            except Exception:
                continue
            tu = _tounicode(f["/ToUnicode"].get_object().get_data()) if "/ToUnicode" in f else {}
            style = name.split("+")[-1]
            inv = {u: c for c, u in tu.items()}
            usual_numbers = not tu or (inv.get("ா", 88) == 88 and inv.get("க", 65) == 65)
            m = {}
            for gid in range(1, len(font.getGlyphOrder())):
                shown = tu.get(gid)
                if shown and any(0x0B80 <= ord(ch) <= 0x0BFF for ch in shown):
                    continue  # the PDF already says which Tamil letters this is
                h = _outline(font, gid)
                if not h:
                    continue
                right = styles.get(style, {}).get(h)
                if right is None:
                    right = everything.get(h)
                if right is None and usual_numbers:
                    right = _standard().get(gid)
                key = shown if shown else chr(gid)
                if right is None or len(key) != 1 or key == right:
                    continue
                m[key] = right
            for n in names:
                maps[n] = m
    return maps


def _font_name(tp, i):
    n = pdfium_c.FPDFText_GetFontInfo(tp.raw, i, None, 0, None)
    if n <= 0:
        return ""
    buf = ctypes.create_string_buffer(n)
    pdfium_c.FPDFText_GetFontInfo(tp.raw, i, buf, n, None)
    return buf.value.decode("utf-8", "replace")


# Vowel signs printed before the letter: put them after it.
_PRE = "ெேை"
_CONS = "[க-ஹ]"
_REORDER = re.compile(rf"([{_PRE}])(க்ஷ|ஸ்ரீ|{_CONS})")


def _fix_order(s):
    s = _REORDER.sub(lambda m: m.group(2) + m.group(1), s)
    s = s.replace("\u0bc6\u0bbe", "\u0bca").replace("\u0bc7\u0bbe", "\u0bcb").replace("\u0bc6\u0bd7", "\u0bcc")
    return s


def _lines(page, maps):
    """[(text, x_left, y)] for one page, with the Tamil repaired."""
    tp = page.get_textpage()
    n = tp.count_chars()
    if n <= 0:
        return []
    # One character at a time, so each one is matched with its own font.
    chars = [chr(pdfium_c.FPDFText_GetUnicode(tp.raw, i)) for i in range(n)]
    out = []
    start = 0
    for end in [i for i, ch in enumerate(chars) if ch in "\r\n"] + [n]:
        pieces = []
        first = None
        idxs = []
        for idx in range(start, end):
            ch = chars[idx]
            if ch in "\r\n" or PUA_RE.match(ch):
                continue
            if ch in "\ufffe\u00ad\u0002":
                pieces.append("-")
                continue
            if ch != " " and not (0x0B80 <= ord(ch) <= 0x0BFF):
                # (Not isspace(): some shapes come out as odd "space" characters, e.g. ஜீ.)
                m = maps.get(_font_name(tp, idx))
                if m:
                    ch = m.get(ch, ch)
            if first is None and not ch.isspace():
                first = idx
            if not ch.isspace():
                idxs.append(idx)
            pieces.append(ch)
        start = end + 1
        line = _fix_order("".join(pieces)).strip()
        if line and first is not None:
            try:
                left = tp.get_charbox(first, loose=True)[0]
                pick = idxs[:: max(1, len(idxs) // 9)]
                ys = sorted(tp.get_charbox(k, loose=True)[1] for k in pick)
                bottom = ys[len(ys) // 2]
            except Exception:
                left, bottom = 0.0, 0.0
            out.append((line, left, bottom))
    return out


_TITLES = None


def _title_from_list(code):
    """Tamil title from Documents\\VGR\\vgr_tamil_list.csv (saved by the download script)."""
    global _TITLES
    if _TITLES is None:
        _TITLES = {}
        p = Path.home() / "Documents" / "VGR" / "vgr_tamil_list.csv"
        if p.exists():
            try:
                with p.open(encoding="utf-8-sig") as fh:
                    for row in csv.DictReader(fh):
                        if row.get("Code") and row.get("Title"):
                            _TITLES[row["Code"].upper()] = row["Title"].strip()
            except Exception:
                pass
    return _TITLES.get(code.upper())


def _join(a, b):
    if not a:
        return b
    if a.endswith(("—", "…", "-")):
        return a + b
    return a + " " + b


def parse_vgr_tamil_pdf(path):
    src = Path(path)
    m = CODE_RE.match(src.stem)
    if not m:
        print(f"SKIPPED {src.name}: no code in the file name.")
        return None
    code = m.group(1).upper()
    try:
        maps = _font_maps(src)
        doc = pdfium.PdfDocument(str(src))
        pages = [_lines(p, maps) for p in doc]
        doc.close()
    except Exception as e:
        print(f"SKIPPED {src.name}: cannot read ({e}).")
        return None

    # Drop the information page and the copyright notice at the end.
    end = len(pages)
    for k in range(len(pages) - 1, max(-1, len(pages) - 4), -1):
        joined = " ".join(t for t, _x, _y in pages[k])
        if ("ALL RIGHTS RESERVED" in joined.upper() or "Copyright Notice" in joined
                or "பதிப்புரிமை அறிவிப்பு" in joined):
            end = k
    pages = pages[:end]

    gaps = sorted(a[2] - b[2] for pg in pages for a, b in zip(pg, pg[1:]) if 5 < a[2] - b[2] < 30)
    line_gap = gaps[len(gaps) // 2] if gaps else 12.0

    title_lines = []
    for pno, pg in enumerate(pages):
        if not pg:
            continue
        if pno == 0:
            # Title at the top, then a clearly bigger space before the text.
            # (A title can take two lines, also with a big space between them: take the last one.)
            cut = 0
            for k in range(1, min(4, len(pg))):
                if pg[k - 1][2] - pg[k][2] > line_gap * 1.8:
                    cut = k
            if cut:
                title_lines = [t for t, _x, _y in pg[:cut]]
                pages[0] = pg[cut:]
        elif len(pg) > 1 and re.search(r"(^\d+\s)|(\s\d+$)", pg[0][0]) and len(pg[0][0]) < 70:
            # Running header "2 உரைக்கப்பட்ட வார்த்தை" / "<title> 3".
            pages[pno] = pg[1:]

    paragraphs = []
    expected = 2
    starts = []
    for pg in pages:
        if not pg:
            continue
        margin = min(x for _t, x, _y in pg)
        for text, x, _y in pg:
            mm = re.match(r"^(\d+)\s+\S", text)
            if mm and x - margin < 6:
                starts.append(int(mm.group(1)))
    for k, c in enumerate(starts):
        later = set(starts[k + 1:k + 12])
        if sum(1 for d in range(1, 6) if c + d in later) >= 4:
            expected = c
            break
    first_number = expected - 1

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

    prev_indent = 0.0
    for pno, pg in enumerate(pages):
        if not pg:
            continue
        margin = min(x for _t, x, _y in pg)
        prev_y = None
        for li, (text, x, y) in enumerate(pg):
            indent = x - margin
            spaced = prev_y is not None and (prev_y - y) > line_gap * 1.42 and indent > 6
            prev_y = y
            num = re.match(r"^(\d+)\s+(.*)$", text)
            if num and int(num.group(1)) == expected and indent < 6:
                flush()
                current = f"{expected}  {num.group(2)}"
                expected += 1
            elif spaced or (indent > prev_indent + 4 and not (pno == 0 and li < 4 and not paragraphs)) \
                    or not current:
                flush()
                current = text
            else:
                current = _join(current, text)
            prev_indent = indent
    flush()

    if not paragraphs:
        print(f"SKIPPED {src.name}: no text found.")
        return None
    if not re.match(r"^\d+\s\s", paragraphs[0]):
        paragraphs[0] = f"{first_number}  " + paragraphs[0]

    title = _title_from_list(code) or " ".join(title_lines).strip() or code
    heading = [{"k": "title", "t": title}, {"k": "info", "t": code}]
    return code, title, paragraphs, heading


if __name__ == "__main__":
    for a in sys.argv[1:]:
        r = parse_vgr_tamil_pdf(a)
        if r:
            code, title, paras, heading = r
            print(code, "|", title, "|", len(paras), "paragraphs")
            for x in paras[:5] + ["..."] + paras[-2:]:
                print("   ", x[:160])
