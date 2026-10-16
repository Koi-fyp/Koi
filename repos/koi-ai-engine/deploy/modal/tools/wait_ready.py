"""Wait until a URL answers over HTTP (cold start can take 60-190 s; Modal caps one request at ~150 s).
Usage: python wait_ready.py <URL> [attempts=8] [sleep_s=25]
Any HTTP status below 500 counts as "up". Exit 0 if up, 1 if not.
"""
import sys
import time
import urllib.error
import urllib.request as _ur
_ur.HTTPRedirectHandler.max_repeats = 200      # Modal answers slow (cold-start) requests with HTTP 303 poll redirects
_ur.HTTPRedirectHandler.max_redirections = 200  # to the SAME url; urllib's default limit (4 repeats) gives up too early
import urllib.request


def main(argv):
    url = argv[0]
    attempts = int(argv[1]) if len(argv) > 1 else 8
    pause = int(argv[2]) if len(argv) > 2 else 25
    for i in range(1, attempts + 1):
        t0 = time.time()
        try:
            with urllib.request.urlopen(url, timeout=170) as r:
                body = r.read(400).decode("utf-8", "replace")
                print("attempt %d: HTTP %d after %.0fs  %s" % (i, r.status, time.time() - t0, body))
                return 0
        except urllib.error.HTTPError as e:
            print("attempt %d: HTTP %d after %.0fs" % (i, e.code, time.time() - t0))
            if e.code < 500:
                return 0
        except Exception as e:
            print("attempt %d: %s after %.0fs" % (i, type(e).__name__, time.time() - t0))
        time.sleep(pause)
    print("NOT READY after %d attempts" % attempts)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
