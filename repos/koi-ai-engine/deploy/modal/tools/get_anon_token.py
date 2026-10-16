"""Get a Firebase ANONYMOUS ID token through Firebase's public REST API (stdlib only).

Usage:
    python get_anon_token.py <WEB_API_KEY> [--sa <path to service-account.json>] [--show] [--token-file <path>]

WEB_API_KEY = the web app's apiKey (Firebase console > Project settings > General > Your apps,
or NEXT_PUBLIC_FIREBASE_API_KEY in the web repo). It is a public identifier, not a secret.

What it proves:
  - anonymous sign-in is enabled for that Firebase project
  - which Firebase project the token belongs to ("aud")
  - with --sa: whether that project is the SAME one the Modal service account belongs to
    (the backend rejects tokens from any other project with 401). Only project_id is read from the file.
By default the token is NOT printed (logs stay clean). --show prints a paste-ready line `set KOI_TOKEN=...`
(token lives ~1 hour). --token-file writes the bare token to a file, for scripts.
"""
import base64
import json
import sys
import time
import urllib.error
import urllib.request

HINTS = {
    "ADMIN_ONLY_OPERATION": "Anonymous sign-in is DISABLED. Firebase console > Authentication > Sign-in method > Anonymous > Enable.",
    "OPERATION_NOT_ALLOWED": "Anonymous sign-in is DISABLED. Firebase console > Authentication > Sign-in method > Anonymous > Enable.",
    "API_KEY_INVALID": "The API key is wrong or belongs to another project.",
    "API key not valid. Please pass a valid API key.": "The API key is wrong or belongs to another project.",
}


def _claims(token):
    seg = token.split(".")[1]
    seg += "=" * (-len(seg) % 4)
    return json.loads(base64.urlsafe_b64decode(seg))


def main(argv):
    if not argv or argv[0].startswith("-"):
        print(__doc__)
        return 2
    key = argv[0]
    def opt(name):
        return argv[argv.index(name) + 1] if name in argv and argv.index(name) + 1 < len(argv) else None

    sa_path = opt("--sa")
    token_file = opt("--token-file")

    url = "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=" + key
    req = urllib.request.Request(
        url,
        data=json.dumps({"returnSecureToken": True}).encode(),
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            resp = json.load(r)
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        try:
            msg = json.loads(body).get("error", {}).get("message", body)
        except ValueError:
            msg = body
        print("FAILED:", e.code, msg)
        print("HINT:", HINTS.get(msg, "see message above"))
        return 1
    except urllib.error.URLError as e:
        print("FAILED: network error:", e)
        return 1

    token = resp["idToken"]
    c = _claims(token)
    project = c.get("aud")
    print("anonymous sign-in OK")
    print("  firebase project (aud):", project)
    print("  uid (sub)             :", c.get("sub"))
    print("  sign_in_provider      :", c.get("firebase", {}).get("sign_in_provider"))
    print("  expires in            : %d min" % ((c.get("exp", 0) - time.time()) / 60))

    rc = 0
    if sa_path:
        try:
            sa_project = json.load(open(sa_path, encoding="utf-8")).get("project_id")
        except (OSError, ValueError) as e:
            print("  service account       : could not read (%s)" % e)
            sa_project = None
            rc = 1
        if sa_project:
            same = sa_project == project
            print("  service-account project:", sa_project)
            print("  SAME PROJECT?          :", "YES" if same else "NO  <-- backend will return 401 for these tokens")
            if not same:
                rc = 1

    if token_file:
        with open(token_file, "w", encoding="utf-8") as f:
            f.write(token)
        print("  token written to      :", token_file)
    if "--show" in argv:
        print()
        print("Paste into cmd (same window you run smoke_chat.py from):")
        print("set KOI_TOKEN=" + token)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
