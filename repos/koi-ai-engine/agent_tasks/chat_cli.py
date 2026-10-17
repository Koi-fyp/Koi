# Temporary local chat client for the live v1.1 chat service. Not part of the product. Delete after use.
import sys, os, json, time, subprocess, tempfile, urllib.request, urllib.error
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHAT_URL = os.environ.get("KOI_CHAT_URL", "https://ahsulem--koi-chat-api-chatserver-web.us-east.modal.run")
KEYFILE = Path(r"E:\Koi\secrets\firebase_web_api_key.txt")
TOOL = ROOT / "deploy" / "modal" / "tools" / "get_anon_token.py"
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

class Redir(urllib.request.HTTPRedirectHandler):
    max_repeats = 200
    max_redirections = 200
opener = urllib.request.build_opener(Redir)

def mint():
    tf = Path(tempfile.gettempdir()) / "koi_chat_cli_tok.txt"
    try:
        subprocess.run([sys.executable, str(TOOL), KEYFILE.read_text().strip(), "--token-file", str(tf)],
                       capture_output=True, check=True)
        tok = tf.read_text().strip()
    except Exception:
        print("token mint failed - run get_anon_token.py by hand and check the key file path"); sys.exit(1)
    finally:
        tf.unlink(missing_ok=True)
    return tok

S = {"tok": None, "t": 0.0, "hist": [], "ex": None}

def token():
    if S["tok"] is None or time.time() - S["t"] > 50 * 60:
        S["tok"], S["t"] = mint(), time.time()
    return S["tok"]

def turn(message):
    body = {"message": message, "session_history": S["hist"], "client_event": "none"}
    if S["ex"]:
        body["exercise_state"] = S["ex"]
    for attempt in range(2):
        req = urllib.request.Request(CHAT_URL + "/api/v1/chat", data=json.dumps(body).encode(), method="POST",
            headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json", "Accept": "text/event-stream"})
        try:
            r = opener.open(req, timeout=240)
            break
        except urllib.error.HTTPError as e:
            if e.code in (401, 403) and attempt == 0:
                S["tok"] = None
                continue
            print("HTTP", e.code); return None
    deltas, info, ev = [], {}, None
    for raw in r:
        line = raw.decode("utf-8").rstrip("\r\n")
        if line.startswith("event:"):
            ev = line[6:].strip()
        elif line.startswith("data:"):
            try:
                d = json.loads(line[5:].strip())
            except ValueError:
                d = line[5:].strip()
            if ev == "delta":
                t = d if isinstance(d, str) else next((d[k] for k in ("text", "delta", "content") if k in d), None)
                if t is None:
                    t = "?? " + repr(d)
                deltas.append(t); print(t, end="", flush=True)
            elif ev == "state" and isinstance(d, dict):
                S["ex"] = d.get("exercise_state")
            elif ev in ("companion_state", "latency", "done"):
                info[ev] = d
    print()
    done = info.get("done") or {}
    reply = done.get("full_text") if isinstance(done, dict) and "full_text" in done else "".join(deltas)
    S["hist"] += [{"role": "user", "content": message}, {"role": "assistant", "content": reply}]
    meta = "emotion=%s | latency=%s | total_s=%s | risk=%s | backend=%s | fallback=%s" % (
        json.dumps(info.get("companion_state")), json.dumps(info.get("latency")),
        done.get("total_generation_s") if isinstance(done, dict) else None,
        json.dumps(done.get("risk"))[:120] if isinstance(done, dict) else None,
        done.get("reply_backend") if isinstance(done, dict) else None,
        done.get("reply_fallback_reason") if isinstance(done, dict) else None)
    print("   [" + meta + "]")
    return reply, meta

def main():
    batch = None
    if len(sys.argv) > 2 and sys.argv[1] == "--batch":
        batch = [l.strip() for l in Path(sys.argv[2]).read_text(encoding="utf-8").splitlines() if l.strip() and not l.startswith("#")]
    logdir = ROOT / "agent_tasks" / "reports" / "chat_sessions"
    logdir.mkdir(parents=True, exist_ok=True)
    lf = open(logdir / ("chat_%s.txt" % datetime.now().strftime("%Y%m%d_%H%M%S")), "w", encoding="utf-8")
    print("warming service (first call after idle can take 60-190 s)...")
    try:
        opener.open(CHAT_URL + "/health", timeout=240).read()
    except Exception as e:
        print("health warm-up failed:", type(e).__name__)
    msgs = iter(batch) if batch is not None else None
    while True:
        if msgs is not None:
            m = next(msgs, None)
            S["hist"], S["ex"] = [], None
            if m is None:
                break
            print("\nYOU> " + m)
        else:
            m = input("\nYOU> ").strip()
            if m == "/quit":
                break
            if m == "/reset":
                S["hist"], S["ex"] = [], None; print("(history cleared)"); continue
            if not m:
                continue
        print("KOI> ", end="", flush=True)
        res = turn(m)
        if res:
            lf.write("[%s] YOU: %s\nKOI: %s\n   %s\n\n" % (datetime.now().strftime("%H:%M:%S"), m, res[0], res[1])); lf.flush()
    lf.close()

main()
