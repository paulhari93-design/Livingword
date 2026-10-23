"""Creates lib/firebase_options.dart from your google-services.json.

Usage: python tools/make_firebase_options.py "<path to google-services.json>"
(setup_and_run.bat and build_apk.bat run this automatically.)
"""
import json
import sys
from pathlib import Path

PACKAGE = "com.livingword.tamil"
OUT = Path(__file__).resolve().parent.parent / "lib" / "firebase_options.dart"


def main():
    src = Path(sys.argv[1])
    if not src.exists():
        print(f"(no {src.name} yet - the app will run without the cloud)")
        return
    g = json.loads(src.read_text(encoding="utf-8"))
    info = g["project_info"]
    client = next((c for c in g["client"]
                   if c["client_info"]["android_client_info"]["package_name"] == PACKAGE), None)
    if client is None:
        sys.exit(f"google-services.json has no Android app '{PACKAGE}'. "
                 "In Firebase, add an Android app with exactly that package name.")
    values = {
        "apiKey": client["api_key"][0]["current_key"],
        "appId": client["client_info"]["mobilesdk_app_id"],
        "messagingSenderId": info["project_number"],
        "projectId": info["project_id"],
        "storageBucket": info.get("storage_bucket", ""),
    }
    body = ",\n".join(f"  {k}: '{v}'" for k, v in values.items())
    dart = ("// Generated from google-services.json by tools/make_firebase_options.py.\n"
            "import 'package:firebase_core/firebase_core.dart';\n\n"
            "const FirebaseOptions? firebaseOptions = FirebaseOptions(\n" + body + ",\n);\n")
    if not OUT.exists() or OUT.read_text(encoding="utf-8") != dart:
        OUT.write_text(dart, encoding="utf-8")
        print(f"Firebase settings written for project '{values['projectId']}'.")
    else:
        print("Firebase settings: up to date.")


if __name__ == "__main__":
    main()
