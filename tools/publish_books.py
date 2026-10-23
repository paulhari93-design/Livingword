"""Publish the books in APP_Books to Firebase, so they appear in the app.

What it does each time you run it:
  * converts every Word file in the APP_Books folder,
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
import hashlib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from docx_to_json import parse_docx  # noqa: E402

PROJECT = Path(__file__).resolve().parent.parent
TOPIC = "new_messages"


def compact(obj) -> str:
    return json.dumps(obj, ensure_ascii=False, separators=(",", ":"))


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


def send_notification(new_items):
    from firebase_admin import messaging

    if len(new_items) == 1:
        title = "புதிய செய்தி / New Message"
        body = f"{new_items[0]['code']}  {new_items[0]['title']}"
    else:
        title = f"{len(new_items)} புதிய செய்திகள் / New Messages"
        body = ", ".join(i["title"] for i in new_items[:3]) + ("…" if len(new_items) > 3 else "")
    msg = messaging.Message(
        topic=TOPIC,
        notification=messaging.Notification(title=title, body=body),
        data={"type": "new_message", "codes": ",".join(i["code"] for i in new_items)},
        android=messaging.AndroidConfig(priority="high"),
    )
    print("Notification sent:", messaging.send(msg))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--books", required=True)
    ap.add_argument("--key", required=True)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--no-notify", action="store_true")
    ap.add_argument("--remove", action="append", default=[])
    ap.add_argument("--force", action="store_true", help="re-upload every book (silently)")
    args = ap.parse_args()

    folder = Path(args.books)
    if not folder.is_dir():
        sys.exit(f"Books folder not found: {folder}")

    # 1) Read and convert the Word files
    local = {}
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
        if code in local:
            print(f"WARNING: two files have code {code}; using {f.name}")
        text = compact({"code": code, "title": title, "heading": heading, "paragraphs": paragraphs})
        local[code] = {"code": code, "title": title, "json": text, "version": version_of(text)}
    print(f"Found {len(local)} books in {folder}")

    db = connect(Path(args.key))

    # 2) Compare with what is already in Firebase
    cat_ref = db.document("catalog/messages")
    snap = cat_ref.get()
    cloud = {i["code"]: i for i in (snap.to_dict() or {}).get("items", [])} if snap.exists else {}

    first_publish = not cloud
    new, changed = [], []
    for code, b in local.items():
        if code not in cloud:
            new.append(b)
        elif args.force or cloud[code]["version"] != b["version"] or cloud[code]["title"] != b["title"]:
            changed.append(b)
    missing = sorted(set(cloud) - set(local))

    for b in new:
        print(f"  NEW        {b['code']}  {b['title']}")
    for b in changed:
        print(f"  CORRECTED  {b['code']}  {b['title']}")
    if missing:
        print("  Note: in the app but not in your folder (kept): " + ", ".join(missing)
              + "\n        To take one out: publish_books.bat --remove CODE")
    if not new and not changed and not args.remove:
        print("Nothing new or changed. The app is up to date.")

    if args.dry_run:
        print("(dry run: nothing uploaded)")
        upload_bible_if_missing(db, dry_run=True)
        return

    # 3) Upload new and corrected books, then the list
    for b in new + changed:
        db.document(f"messages/{b['code']}").set(
            {"code": b["code"], "title": b["title"], "version": b["version"], "json": b["json"]})
        cloud[b["code"]] = {"code": b["code"], "title": b["title"], "version": b["version"]}
    for code in args.remove:
        if code in cloud:
            del cloud[code]
            db.document(f"messages/{code}").delete()
            print(f"  REMOVED    {code}")
    if new or changed or args.remove:
        items = sorted(cloud.values(), key=lambda i: i["code"])
        cat_ref.set({"items": items})
        print(f"Uploaded. The app now has {len(items)} messages.")

    upload_bible_if_missing(db, dry_run=False)

    # 4) One notification for NEW books only (corrections stay silent).
    #    The very first upload fills an empty app, so no notification then.
    if new and not args.no_notify and first_publish:
        print("First upload: no notification sent (the app was empty).")
    elif new and not args.no_notify:
        send_notification(new)


if __name__ == "__main__":
    main()
