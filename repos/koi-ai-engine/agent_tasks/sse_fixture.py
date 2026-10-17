import os, sys, json, time, urllib.request, urllib.error
from datetime import datetime
from pathlib import Path
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
URL = (sys.argv[1] if len(sys.argv) > 1 else "https://ahsulem--koi-chat-api-chatserver-web.us-east.modal.run").rstrip("/")
TOKEN = os.environ.get("KOI_TOKEN", "")
if not TOKEN:
    sys.exit("set KOI_TOKEN first")

class Redir(urllib.request.HTTPRedirectHandler):
    max_repeats = 200
    max_redirections = 200
opener = urllib.request.build_opener(Redir)

CASES = [
    ("normal_chat", {"message": "I have a presentation tomorrow and I feel anxious.", "session_history": [], "client_event": "none"}),
    ("exercise_start", {"message": "can we do a breathing exercise", "session_history": [], "client_event": "start_breathing"}),
    ("high_risk_tier", {"message": "My dog passed away today", "session_history": [], "client_event": "none"}),
]

def clean(o):
    if isinstance(o, dict):
        out = {}
        for k, v in o.items():
            if k == "trace":
                out[k] = "<removed>"
            elif k == "exercise_state" and isinstance(v, str):
                out[k] = v[:10] + "...<truncated>"
            else:
                out[k] = clean(v)
        return out
    if isinstance(o, list):
        return [clean(x) for x in o]
    return o

outdir = Path("agent_tasks/reports/fixtures")
outdir.mkdir(parents=True, exist_ok=True)
fn = outdir / ("sse_fixtures_%s.txt" % datetime.now().strftime("%Y%m%d_%H%M%S"))
with open(fn, "w", encoding="utf-8") as f:
    f.write("# Redacted SSE fixtures from the live chat service (no tokens; exercise_state truncated; trace removed).\n")
    f.write("# Captured %s PKT. Rely on event order and field names; reply wording varies.\n\n" % datetime.now().strftime("%Y-%m-%d %H:%M"))
    for name, body in CASES:
        f.write("=== %s ===\nREQUEST: %s\n" % (name, json.dumps(body)))
        req = urllib.request.Request(URL + "/api/v1/chat", data=json.dumps(body).encode(), method="POST",
            headers={"Authorization": "Bearer " + TOKEN, "Content-Type": "application/json", "Accept": "text/event-stream"})
        t = time.time()
        try:
            r = opener.open(req, timeout=240)
        except urllib.error.HTTPError as e:
            f.write("HTTP %d\n\n" % e.code); print(name, "HTTP", e.code); continue
        except Exception as e:
            f.write("exception %s\n\n" % type(e).__name__); print(name, "exception", type(e).__name__); continue
        ev, n = None, 0
        for raw in r:
            line = raw.decode("utf-8").rstrip("\r\n")
            if line.startswith("event:"):
                ev = line[6:].strip()
            elif line.startswith("data:"):
                txt = line[5:].strip()
                try:
                    txt = json.dumps(clean(json.loads(txt)), ensure_ascii=False)
                except ValueError:
                    pass
                n += 1
                f.write("%02d +%.2fs event: %s\n   data: %s\n" % (n, time.time() - t, ev, txt))
        f.write("\n")
        print(name, "ok", n, "events")
        time.sleep(3)
print("wrote", fn)