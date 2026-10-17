"""Cold-start probe for the KOI chat service (stdlib only; acceptance kit, Work Package A).

Usage (koivenv, cmd):
    set PYTHONDONTWRITEBYTECODE=1
    python agent_tasks\\acceptance\\cold_start_probe.py <CHAT_URL> [--event start_breathing] [--message TEXT]

1. GET  <CHAT_URL>/health   (no token)
2. POST <CHAT_URL>/api/v1/chat with the Firebase ID token from env KOI_TOKEN (never printed, never written).
Redirects (Modal answers a request still running after ~150 s with HTTP 303 to a poll URL) are followed MANUALLY
with http.client, so every hop is visible. Per hop: elapsed seconds since the step started, status, and the Location
host + path only (the query string is never printed). For the POST: time to the first SSE event, event names in
order, and a short risk/handoff summary. Always exits 0: it is a measurement, not a gate.

--event start_breathing sends client_event "start_breathing" so that, on a truly cold system, the same request also
shows what the director does when the server's crisis score is not ready in time (risk "unavailable").
"""
import http.client
import json
import os
import sys
import time
import urllib.parse

sys.dont_write_bytecode = True

HOP_TIMEOUT_S = 200      # one hop; Modal itself caps a single HTTP request at ~150 s and then answers 303
MAX_HOPS = 20
OVERALL_S = 600


def _conn(url):
    parts = urllib.parse.urlsplit(url)
    cls = http.client.HTTPSConnection if parts.scheme == "https" else http.client.HTTPConnection
    path = parts.path or "/"
    if parts.query:
        path += "?" + parts.query
    return cls(parts.netloc, timeout=HOP_TIMEOUT_S), path, parts


def _safe(url):
    """host + path only; never the query (poll ids) and never credentials."""
    p = urllib.parse.urlsplit(url)
    return "%s%s" % (p.hostname or "", p.path or "/")


def request_following(method, url, body=None, headers=None, label=""):
    """Follow 301/302/303/307/308 by hand. Returns (response, conn, hops, t0) with the final response unread."""
    headers = dict(headers or {})
    t0 = time.monotonic()
    origin_host = urllib.parse.urlsplit(url).hostname
    hops = []
    for n in range(1, MAX_HOPS + 1):
        if time.monotonic() - t0 > OVERALL_S:
            raise TimeoutError("overall %d s budget exceeded" % OVERALL_S)
        conn, path, parts = _conn(url)
        send_headers = dict(headers)
        if parts.hostname != origin_host:
            send_headers.pop("Authorization", None)      # never forward the token to another host
        conn.request(method, path, body=body, headers=send_headers)
        resp = conn.getresponse()
        elapsed = time.monotonic() - t0
        loc = resp.getheader("Location")
        hop = {"hop": n, "method": method, "elapsed_s": round(elapsed, 2), "status": resp.status,
               "location": _safe(urllib.parse.urljoin(url, loc)) if loc else None}
        hops.append(hop)
        print("  %s hop %d: %-4s elapsed=%7.2fs status=%d%s" % (
            label, n, method, elapsed, resp.status, ("  Location=" + hop["location"]) if loc else ""))
        if resp.status in (301, 302, 303, 307, 308) and loc:
            resp.read()
            conn.close()
            url = urllib.parse.urljoin(url, loc)
            if resp.status == 303 or (resp.status in (301, 302) and method == "POST"):
                method, body = "GET", None
                headers.pop("Content-Type", None)
            continue
        return resp, conn, hops, t0
    raise RuntimeError("more than %d redirects" % MAX_HOPS)


def sse_events(resp):
    event, data = None, []
    while True:
        raw = resp.readline()
        if not raw:
            break
        line = raw.decode("utf-8", "replace").rstrip("\r\n")
        if not line:
            if event is not None:
                try:
                    payload = json.loads("\n".join(data)) if data else None
                except ValueError:
                    payload = {"_unparsed": True}
                yield event, payload
            event, data = None, []
        elif line.startswith("event:"):
            event = line[6:].strip()
        elif line.startswith("data:"):
            data.append(line[5:].lstrip())


def main(argv):
    args = [a for a in argv]
    if not args or args[0].startswith("-"):
        print(__doc__)
        return 0
    base = args[0].rstrip("/")
    def opt(name, default=None):
        return args[args.index(name) + 1] if name in args and args.index(name) + 1 < len(args) else default
    event = opt("--event", "none")
    message = opt("--message", "can we do a breathing exercise" if event == "start_breathing" else "hey, what's up?")
    print("cold_start_probe  target=%s  started=%s" % (_safe(base), time.strftime("%Y-%m-%d %H:%M:%S")))

    print("[1] GET /health")
    try:
        resp, conn, hops, t0 = request_following("GET", base + "/health", label="health")
        body = resp.read()
        conn.close()
        print("  health total=%.2fs status=%d body=%s" % (time.monotonic() - t0, resp.status,
                                                          body[:120].decode("utf-8", "replace")))
    except Exception as exc:  # noqa: BLE001 - measurement only
        print("  health FAILED: %s: %s" % (type(exc).__name__, str(exc)[:160]))

    token = os.environ.get("KOI_TOKEN", "").strip()
    if not token:
        print("[2] POST /api/v1/chat SKIPPED: KOI_TOKEN is not set")
        return 0
    print("[2] POST /api/v1/chat  client_event=%s  message=%r" % (event, message))
    payload = {"message": message, "session_history": [], "exercise_state": None, "client_event": event}
    try:
        resp, conn, hops, t0 = request_following(
            "POST", base + "/api/v1/chat", body=json.dumps(payload).encode("utf-8"),
            headers={"Authorization": "Bearer " + token, "Content-Type": "application/json",
                     "Accept": "text/event-stream"}, label="chat")
        token = None
        ctype = resp.getheader("Content-Type") or ""
        if resp.status != 200 or "text/event-stream" not in ctype:
            print("  chat final status=%d content-type=%s body=%s" % (
                resp.status, ctype, resp.read()[:200].decode("utf-8", "replace")))
            conn.close()
            return 0
        names, first_s, done, risk, ui, handoff = [], None, None, None, [], False
        for name, data in sse_events(resp):
            if first_s is None:
                first_s = time.monotonic() - t0
                print("  first SSE event after %.2fs (%s)" % (first_s, name))
            names.append(name)
            if name == "risk":
                risk = data
            elif name == "ui_action" and isinstance(data, dict):
                ui.append(data.get("name"))
            elif name == "handoff":
                handoff = True
            elif name == "done":
                done = data
        conn.close()
        total = time.monotonic() - t0
        print("  stream closed after %.2fs" % total)
        print("  events: %s" % " ".join(names))
        if isinstance(risk, dict):
            print("  risk: status=%s category=%s score=%s" % (risk.get("status"), risk.get("risk_category"),
                                                             risk.get("crisis_score")))
        print("  ui_actions=%s handoff=%s" % (ui, handoff))
        if isinstance(done, dict):
            print("  done: reply_backend=%s reply_fallback_reason=%s total_generation_s=%s" % (
                done.get("reply_backend"), done.get("reply_fallback_reason"), done.get("total_generation_s")))
            print("  done.exercise_state present=%s" % isinstance(done.get("exercise_state"), str))
        print("  hops=%d redirects=%d" % (len(hops), len(hops) - 1))
    except Exception as exc:  # noqa: BLE001 - measurement only
        token = None
        print("  chat FAILED: %s: %s" % (type(exc).__name__, str(exc)[:160]))
    return 0


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    finally:
        sys.exit(0)
