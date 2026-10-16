"""Security check: a protected endpoint must reject missing / garbage Firebase tokens.
Usage: python auth_check.py <BASE_URL> <PATH>      e.g.  auth_check.py https://x.modal.run /api/v1/chat
Sends a POST with (a) no Authorization header, (b) 'Bearer garbage'. Both must return 401 (or 403).
Exit 0 if both are rejected, 1 otherwise. Also fails if the response body contains a stack trace.
"""
import json
import sys
import urllib.error
import urllib.request


def post(url, headers):
    req = urllib.request.Request(url, data=json.dumps({"message": "hi", "session_history": []}).encode(),
                                 headers=dict({"Content-Type": "application/json"}, **headers))
    try:
        with urllib.request.urlopen(req, timeout=170) as r:
            return r.status, r.read(300).decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read(300).decode("utf-8", "replace")


def main(argv):
    url = argv[0].rstrip("/") + argv[1]
    bad = 0
    for label, hdr in (("no token", {}), ("garbage token", {"Authorization": "Bearer garbage"})):
        code, body = post(url, hdr)
        ok = code in (401, 403) and "Traceback" not in body
        print("%-14s -> HTTP %s  %s  %s" % (label, code, "OK (rejected)" if ok else "PROBLEM", body[:100].replace("\n", " ")))
        bad += 0 if ok else 1
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
