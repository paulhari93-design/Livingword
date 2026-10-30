"""Feedback sent from the app (⋮ → Feedback).

    python tools/feedback.py --key <service-account.json>         new feedback (then marked as seen)
    python tools/feedback.py --key <service-account.json> --all   all feedback
"""
import argparse
import sys
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--key", required=True)
    ap.add_argument("--all", action="store_true")
    a = ap.parse_args()

    import firebase_admin
    from firebase_admin import credentials, firestore
    key = Path(a.key)
    if not key.exists():
        sys.exit(f"Key file not found: {key}")
    firebase_admin.initialize_app(credentials.Certificate(str(key)))
    db = firestore.client()

    q = db.collection("feedback")
    if not a.all:
        q = q.where("seen", "==", False)
    docs = list(q.stream())
    docs.sort(key=lambda d: d.to_dict().get("createdAt").timestamp() if d.to_dict().get("createdAt") else 0)
    if not docs:
        print("No new feedback." if not a.all else "No feedback yet.")
        return
    for n, d in enumerate(docs, 1):
        r = d.to_dict()
        when = r.get("createdAt")
        when = when.strftime("%d %b %Y %H:%M") if when else ""
        who = f"{r.get('name')}  ({r.get('contact')})" if r.get("name") else "anonymous"
        print(f"[{n}] {when}   from: {who}")
        print(f"    {r.get('text', '')}")
        print(f"    reading: {r.get('reading', '')}   app {r.get('app', '')}   {r.get('profile', '')}")
        print()
        if not r.get("seen"):
            d.reference.update({"seen": True})
    if not a.all:
        print(f"{len(docs)} new. (They are now marked as seen; read_feedback.bat all shows everything.)")


if __name__ == "__main__":
    main()
