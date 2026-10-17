"""GET /health on chat and crisis WITHOUT a token (the contract: /health needs no token in either service).
Usage: python health_check.py <CHAT_URL> <CRISIS_URL>
PASS needs: chat 200; crisis 200 with max_category == "HIGH" and rag_enabled false. Exit 0 on PASS, 1 on FAIL.
Prints one `RESULT health PASS|FAIL` line plus the non-secret fields it checked.
"""
import json
import sys
import urllib.error
import urllib.request as _ur
_ur.HTTPRedirectHandler.max_repeats = 200      # Modal answers slow (cold-start) requests with HTTP 303 poll redirects
_ur.HTTPRedirectHandler.max_redirections = 200  # to the SAME url; urllib's default limit (4 repeats) gives up too early
import urllib.request

TIMEOUT_S = 240


def get(url):
    try:
        with urllib.request.urlopen(urllib.request.Request(url), timeout=TIMEOUT_S) as r:
            return r.status, json.loads(r.read().decode("utf-8", "replace") or "null")
    except urllib.error.HTTPError as e:
        return e.code, None
    except Exception as e:  # timeout, DNS, bad JSON
        return type(e).__name__, None


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    problems = []
    chat_code, _ = get(argv[0].rstrip("/") + "/health")
    print("chat   /health -> %s" % chat_code)
    if chat_code != 200:
        problems.append("chat /health %s" % chat_code)
    crisis_code, body = get(argv[1].rstrip("/") + "/health")
    body = body if isinstance(body, dict) else {}
    print("crisis /health -> %s  max_category=%r rag_enabled=%r rag_assets_loaded=%r auth_disabled=%r" % (
        crisis_code, body.get("max_category"), body.get("rag_enabled"), body.get("rag_assets_loaded"),
        body.get("auth_disabled")))
    if crisis_code != 200:
        problems.append("crisis /health %s" % crisis_code)
    else:
        if body.get("max_category") != "HIGH":
            problems.append("crisis max_category %r != 'HIGH'" % body.get("max_category"))
        if body.get("rag_enabled") is not False:
            problems.append("crisis rag_enabled %r (expected false)" % body.get("rag_enabled"))
    print("RESULT %-17s %s%s" % ("health", "FAIL" if problems else "PASS", ("  " + "; ".join(problems)) if problems else ""))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
