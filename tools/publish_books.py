"""Publish the books in APP_Books to Firebase, so they appear in the app.

What it does each time you run it:
  * converts every Word file in the APP_Books folder (Tamil),
  * converts every English message in APP_Books/English (from download_english.bat),
  * uploads only books that are NEW or CHANGED (corrected),
  * sends ONE phone notification for new books (corrections are silent),
  * uploads the Bible the first time (only if it isn't in Firebase yet).

Usage (publish_books.bat runs this for you):
    python tools/publish_books.py --books "<APP_Books folder>" --key "<service-account.json>"
Options:
    --dry-run      only show what would happen, upload nothing
    --no-notify    upload new books without sending a notification
    --remove CODE  take a book out of the app (e.g. --remove 53-0218)
"""
import argparse
import base64
import gzip
import hashlib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from docx_to_json import parse_docx  # noqa: E402
from messagehub_to_json import parse_messagehub
from vgr_pdf_to_json import parse_vgr_pdf  # noqa: E402
from vgr_tamil_pdf import parse_vgr_tamil_pdf  # noqa: E402
from align import align  # noqa: E402

PROJECT = Path(__file__).resolve().parent.parent
TOPIC = "new_messages"


def compact(obj) -> str:
    return json.dumps(obj, ensure_ascii=False, separators=(",", ":"))


def zipped(text: str) -> str:
    """The message JSON gzip-compressed and base64-encoded (about 4-6x smaller)."""
    return base64.b64encode(gzip.compress(text.encode("utf-8"), 9)).decode("ascii")


def version_of(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def connect(key_path: Path):
    import firebase_admin
    from firebase_admin import credentials, firestore

    if not key_path.exists():
        sys.exit(f"Key file not found: {key_path}\n"
                 "Put service-account.json in Documents\\livingword_keys (see the setup steps).")
    firebase_admin.initialize_app(credentials.Certificate(str(key_path)))
    return firestore.client()


def upload_bible_if_missing(db, dry_run: bool):
    meta = db.document("catalog/bible").get()
    if meta.exists:
        print("Bible: already in Firebase.")
        return
    bible = PROJECT / "assets" / "bible"
    books = json.loads((bible / "books.json").read_text(encoding="utf-8"))
    print(f"Bible: uploading {len(books)} Tamil + {len(books)} English books (first time only)...")
    if dry_run:
        return
    for b in books:
        for lang, folder in (("ta", bible), ("en", bible / "kjv")):
            data = json.loads((folder / b["f"]).read_text(encoding="utf-8"))
            text = compact({"c": data["c"]})
            db.document(f"bible_{lang}/{b['f'][:-5]}").set({"json": text})
        print(f"  {b['n']:>2}/66 {b['en']}")
    books_text = compact(books)
    db.document("catalog/bible").set({"version": version_of(books_text), "books": books_text})
    print("Bible: done.")


def send_notification(new_items, english=False):
    from firebase_admin import messaging

    if english and len(new_items) == 1:
        title = "New English Message / புதிய ஆங்கில செய்தி"
        body = f"{new_items[0]['code']}  {new_items[0]['title']}"
    elif english:
        title = f"{len(new_items)} New English Messages"
        body = ", ".join(i["title"] for i in new_items[:3]) + ("…" if len(new_items) > 3 else "")
    elif len(new_items) == 1:
        title = "புதிய செய்தி / New Message"
        body = f"{new_items[0]['code']}  {new_items[0]['title']}"
    else:
        title = f"{len(new_items)} புதிய செய்திகள் / New Messages"
        body = ", ".join(i["title"] for i in new_items[:3]) + ("…" if len(new_items) > 3 else "")
    # Tamil news goes to English+Tamil readers; English news also to English-only readers.
    target = ({"condition": f"'{TOPIC}' in topics || '{TOPIC}_en' in topics"} if english
              else {"topic": TOPIC})
    msg = messaging.Message(
        **target,
        notification=messaging.Notification(title=title, body=body),
        data={"type": "new_message", "codes": ",".join(i["code"] for i in new_items)},
        android=messaging.AndroidConfig(priority="high"),
    )
    print("Notification sent:", messaging.send(msg))


def sync_series(db, dry_run: bool):
    """series.json (next to the .bat files) -> catalog/series, when it changed."""
    path = Path(__file__).resolve().parent.parent / "series.json"
    if not path.exists():
        return
    text = path.read_text(encoding="utf-8")
    data = json.loads(text)  # stops here if the file has a mistake
    version = hashlib.sha1(text.encode("utf-8")).hexdigest()[:12]
    snap = db.document("catalog/series").get()
    if snap.exists and (snap.to_dict() or {}).get("version") == version:
        print("Series: no change.")
        return
    print(f"Series: {len(data)} series {'(dry run)' if dry_run else 'uploaded'}.")
    if not dry_run:
        db.document("catalog/series").set({"version": version,
                                           "json": json.dumps(data, ensure_ascii=False)})


def sync_language(db, local, catalog_path, collection, args, label):
    """Uploads new/changed books of one language. Returns (new, first_publish)."""
    cat_ref = db.document(catalog_path)
    snap = cat_ref.get()
    cloud = {i["code"]: i for i in (snap.to_dict() or {}).get("items", [])} if snap.exists else {}

    first_publish = not cloud
    new, changed, compress = [], [], []
    for code, b in local.items():
        if code not in cloud:
            new.append(b)
        elif args.force or cloud[code]["version"] != b["version"] or cloud[code]["title"] != b["title"]:
            changed.append(b)
        elif not cloud[code].get("z"):
            compress.append(b)  # already in the app, but not yet in the smaller (compressed) form
    removing = [c for c in cloud if c.upper() in {r.upper() for r in args.remove}]
    if args.prune:
        # Take out everything that is in the app but no longer in your folders.
        removing = sorted(set(removing) | (set(cloud) - set(local)))
    missing = sorted(set(cloud) - set(local) - set(removing))

    print(f"{label}:")
    for b in new:
        print(f"  NEW        {b['code']}  {b['title']}")
    for b in changed:
        print(f"  CORRECTED  {b['code']}  {b['title']}")
    if missing:
        print("  Note: in the app but not in your folder (kept): " + ", ".join(missing)
              + "\n        To take one out: remove_book.bat")
    for code in removing:
        print(f"  TO REMOVE  {code}  {cloud[code].get('title', '')}")
    if compress:
        print(f"  Making {len(compress)} messages smaller for download (no change for readers)...")
    if not new and not changed and not removing and not compress:
        print("  Nothing new or changed.")

    if args.dry_run:
        return [], first_publish

    for b in new + changed:
        # Full text (read by older app versions) ...
        db.document(f"{collection}/{b['code']}").set(
            {"code": b["code"], "title": b["title"], "version": b["version"], "json": b["json"]})
    for b in new + changed + compress:
        # ... and the compressed copy the app downloads now.
        db.document(f"{collection}_z/{b['code']}").set({"version": b["version"], "z": zipped(b["json"])})
        cloud[b["code"]] = {"code": b["code"], "title": b["title"], "version": b["version"], "z": True}
    for code in removing:
        del cloud[code]
        db.document(f"{collection}/{code}").delete()
        db.document(f"{collection}_z/{code}").delete()
        print(f"  REMOVED    {code}")
    if new or changed or removing or compress:
        items = sorted(cloud.values(), key=lambda i: i["code"])
        cat_ref.set({"items": items})
        print(f"  Uploaded. The app now has {len(items)} {label.lower()}.")
    return new, first_publish


def add_book(local, code, title, paragraphs, heading, name, extra=None):
    if code in local:
        print(f"WARNING: two files have code {code}; using {name}")
    data = {"code": code, "title": title, "heading": heading, "paragraphs": paragraphs}
    data.update(extra or {})
    text = compact(data)
    local[code] = {"code": code, "title": title, "json": text, "version": version_of(text)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--books", required=True)
    ap.add_argument("--key", required=True)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--no-notify", action="store_true")
    ap.add_argument("--remove", action="append", default=[])
    ap.add_argument("--prune", action="store_true",
                    help="remove from the app every message that is not in your folders")
    ap.add_argument("--force", action="store_true", help="re-upload every book (silently)")
    args = ap.parse_args()

    folder = Path(args.books)
    if not folder.is_dir():
        sys.exit(f"Books folder not found: {folder}")

    # 1a) Tamil: the Word files in APP_Books
    tamil = {}
    tamil_parsed = []
    for f in sorted(folder.glob("*.docx")):
        if f.name.startswith("~$"):  # Word's temporary lock file while a document is open
            continue
        parsed = parse_docx(f)
        if not parsed:
            continue
        code, title, paragraphs, heading = parsed
        inside = [h["t"].strip("() ") for h in heading if h["k"] == "info"]
        inside = [t for t in inside if re.fullmatch(r"\d{2}-\d{4}[A-Za-z]?", t)]
        if inside and inside[0].upper() != code.upper():
            print(f"WARNING: {f.name}\n         file name says {code}, but the document says {inside[0]}."
                  f" Please check the file name.")
        tamil_parsed.append((code, title, paragraphs, heading, f.name))

    # 1b) English. First choice: VGR (APP_Books\English_VGR). For any message VGR does not
    #     have, the MessageHub copy (APP_Books\English) is used.
    english = {}
    en_paragraphs = {}
    en_sources = {"VGR": 0, "MessageHub": 0}
    for sub, source in (("English_VGR", "VGR"), ("English", "MessageHub")):
        en_folder = folder / sub
        if not en_folder.is_dir():
            continue
        for f in sorted(list(en_folder.glob("*.messagehub")) + list(en_folder.glob("*.htm*"))
                        + list(en_folder.glob("*.pdf"))):
            if f.suffix.lower() == ".pdf":
                code_m = re.match(r"^(\d{2}-\d{4}[A-Za-z]?)", f.stem)
                if code_m and code_m.group(1).upper() in en_paragraphs:
                    continue
                parsed = parse_vgr_pdf(f)
            else:
                parsed = parse_messagehub(f)
            if not parsed or parsed[0].upper() in en_paragraphs:
                continue
            add_book(english, *parsed, f.name)
            en_paragraphs[parsed[0].upper()] = parsed[2]
            en_sources[source] += 1
    if en_sources["VGR"]:
        print(f"English: {en_sources['VGR']} from VGR, {en_sources['MessageHub']} from MessageHub")

    # 1b2) Tamil, in this order: 1. your own Word files, 2. MessageHub (APP_Books\Tamil_MessageHub),
    #      3. VGR (APP_Books\Tamil_VGR). A message is taken from the first place that has it.
    have = {c.upper() for c, *_ in tamil_parsed}
    for sub, source in (("Tamil_MessageHub", "MessageHub"), ("Tamil_VGR", "VGR")):
        ta_folder = folder / sub
        count = 0
        if not ta_folder.is_dir():
            continue
        for f in sorted(list(ta_folder.glob("*.messagehub")) + list(ta_folder.glob("*.htm*"))
                        + list(ta_folder.glob("*.pdf"))):
            code_m = re.match(r"^(\d{2}-\d{4}[A-Za-z]?)", f.stem)
            if code_m and code_m.group(1).upper() in have:
                continue  # already taken from an earlier place in the order
            parsed = parse_vgr_tamil_pdf(f) if f.suffix.lower() == ".pdf" else parse_messagehub(f)
            if not parsed or parsed[0].upper() in have:
                continue
            code, title, paragraphs, heading = parsed
            tamil_parsed.append((code, title, paragraphs, heading, f.name))
            have.add(code.upper())
            count += 1
        if count:
            print(f"Tamil: using {count} from {source} (for messages not found earlier in the order)")

    # 1c) Match Tamil paragraphs to English paragraphs (for the language switch)
    for code, title, paragraphs, heading, name in tamil_parsed:
        en = en_paragraphs.get(code.upper())
        extra = {"align": align(paragraphs, en)} if en else None
        add_book(tamil, code, title, paragraphs, heading, name, extra)
    print(f"Found {len(tamil)} Tamil books in {folder}")
    print(f"Found {len(english)} English books")

    db = connect(Path(args.key))

    # 2) Compare with Firebase and upload what is new or corrected
    sync_series(db, args.dry_run)
    new_ta, first_ta = sync_language(db, tamil, "catalog/messages", "messages", args, "Messages")
    new_en, first_en = sync_language(db, english, "catalog/messages_en", "messages_en", args,
                                     "English messages")

    if args.dry_run:
        print("(dry run: nothing uploaded)")
        upload_bible_if_missing(db, dry_run=True)
        return

    upload_bible_if_missing(db, dry_run=False)

    # 3) Notifications for NEW books only (corrections stay silent).
    #    The very first upload of a language fills an empty app, so no notification then.
    if args.no_notify:
        return
    if len(new_ta) > 20:
        print(f"{len(new_ta)} new messages at once: no notification sent.")
    elif new_ta and first_ta:
        print("First upload: no notification sent (the app was empty).")
    elif new_ta:
        send_notification(new_ta)
    if len(new_en) > 20:
        print(f"{len(new_en)} new English messages at once: no notification sent.")
    elif new_en and first_en:
        print("First English upload: no notification sent.")
    elif new_en:
        send_notification(new_en, english=True)


if __name__ == "__main__":
    main()
