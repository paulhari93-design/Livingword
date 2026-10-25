"""Read an English message saved from MessageHub (download_english.bat) into the app's format.

The MessageHub page looks like:
    <div class="message-header"><h1>Title</h1><h2>Place</h2><h3>51-0721</h3></div>
    <div class="... wmb"><div class="pnum">1</div>Paragraph text...</div>
    <div class="... wmb">More text of paragraph 1...</div>
    <div class="... scripture">Bible reading...</div>

Each text block becomes one paragraph in the app. A block that starts a numbered
paragraph gets the number in front ("1  It was...."), like the Tamil messages.
"""
import html
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

CODE_RE = re.compile(r"^(\d{2}-\d{4}[A-Za-z]?)")
TEXT_CLASSES = ("wmb", "scripture", "stanza", "singing", "heading")


class _Parser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.header = {}          # h1 / h2 / h3 -> text
        self._in_header_tag = None
        self.blocks = []          # [(pnum or None, kind, text)]
        self._depth = 0           # div depth
        self._block_depth = None  # depth of the current text block div
        self._block_kind = None
        self._in_pnum = False
        self._pnum = None
        self._buf = []

    def handle_starttag(self, tag, attrs):
        cls = dict(attrs).get("class", "") or ""
        if tag in ("h1", "h2", "h3"):
            self._in_header_tag = tag
            self.header[tag] = ""
            return
        if tag == "br" and self._block_depth is not None:
            self._buf.append(" ")
            return
        if tag != "div":
            return
        self._depth += 1
        classes = cls.split()
        if "pnum" in classes and self._block_depth is not None:
            self._in_pnum = True
            return
        kind = next((c for c in classes if c in TEXT_CLASSES), None)
        if kind and self._block_depth is None:
            self._block_depth = self._depth
            self._block_kind = kind
            self._pnum = None
            self._buf = []

    def handle_endtag(self, tag):
        if tag in ("h1", "h2", "h3"):
            self._in_header_tag = None
            return
        if tag != "div":
            return
        if self._in_pnum:
            self._in_pnum = False
        elif self._block_depth is not None and self._depth == self._block_depth:
            text = " ".join("".join(self._buf).split())
            if text:
                self.blocks.append((self._pnum, self._block_kind, text))
            self._block_depth = None
        self._depth -= 1

    def handle_data(self, data):
        if self._in_header_tag:
            self.header[self._in_header_tag] += data
        elif self._in_pnum:
            self._pnum = (self._pnum or "") + data.strip()
        elif self._block_depth is not None:
            self._buf.append(data)


def parse_messagehub(path):
    """Returns (code, title, paragraphs, heading) or None."""
    src = Path(path)
    raw = src.read_text(encoding="utf-8", errors="replace")
    p = _Parser()
    p.feed(raw)

    title = html.unescape(" ".join(p.header.get("h1", "").split()))
    place = html.unescape(" ".join(p.header.get("h2", "").split()))
    code = " ".join(p.header.get("h3", "").split()).upper()
    if not CODE_RE.match(code):
        m = CODE_RE.match(src.stem)
        if not m:
            print(f"SKIPPED {src.name}: no code found.")
            return None
        code = m.group(1).upper()
    title = re.sub(r"\s*\(William Branham\)\s*$", "", title).strip() or code

    paragraphs = []
    for pnum, _kind, text in p.blocks:
        paragraphs.append(f"{pnum}  {text}" if pnum else text)
    if not paragraphs:
        print(f"SKIPPED {src.name}: no text found.")
        return None

    heading = [{"k": "title", "t": title}, {"k": "info", "t": code}]
    if place:
        heading.append({"k": "info", "t": place})
    return code, title, paragraphs, heading


if __name__ == "__main__":
    for a in sys.argv[1:]:
        r = parse_messagehub(a)
        if r:
            code, title, paras, heading = r
            print(code, "|", title, "|", heading[-1]["t"], "|", len(paras), "paragraphs")
            for x in paras[:3]:
                print("   ", x[:110])
