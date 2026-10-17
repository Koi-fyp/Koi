import sys, json, time, subprocess, tempfile, urllib.request, urllib.error
from datetime import datetime
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
ROOT = Path(r"E:\Koi\Koi-App\repos\koi-ai-engine")
PY = r"E:\Setups\anaconda\envs\koivenv\python.exe"
URL = "https://ahsulem--koi-chat-api-chatserver-web.us-east.modal.run"
SECRETS = Path(r"E:\Koi\secrets")
OUT = ROOT / "agent_tasks" / "reports" / "acceptance"
OUT.mkdir(parents=True, exist_ok=True)
LOG = OUT / ("fallback_live_%s.txt" % datetime.now().strftime("%Y%m%d_%H%M%S"))

class Redir(urllib.request.HTTPRedirectHandler):
    max_repeats = 200
    max_redirections = 200
opener = urllib.request.build_opener(Redir)

def log(s):
    line = "[%s] %s" % (datetime.now().strftime("%H:%M:%S"), s)
    print(line, flush=True)
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(line + "\n")

def key(name):
    return (SECRETS / name).read_text(encoding="utf-8").strip()

def run(args, stdin=None):
    r = subprocess.run(args, input=stdin, capture_output=True, text=True, encoding="utf-8",
                       errors="replace", timeout=240, cwd=str(ROOT))
    return r.returncode, (r.stderr or "")[-200:]

def swap(mode):
    k1, k2 = key("gemini_key.txt"), key("groq_key.txt")
    if mode == "broken":
        k1, k2 = "invalid-key-for-fallback-test-1", "invalid-key-for-fallback-test-2"
    lines = ["KOI_LLM_PROVIDER=gemini", "KOI_LLM_MODEL=gemini-3.1-flash-lite", "KOI_LLM_API_KEY=" + k1,
             "KOI_LLM_TIMEOUT_S=8", "KOI_LLM_TOTAL_BUDGET_S=12",
             "KOI_LLM2_PROVIDER=openai_compat", "KOI_LLM2_MODEL=openai/gpt-oss-120b",
             "KOI_LLM2_BASE_URL=https://api.groq.com/openai/v1", "KOI_LLM2_API_KEY=" + k2,
             "KOI_API_ON_HANDOFF=1"]
    envfile = Path(tempfile.gettempdir()) / "koi_llm_swap.env"
    envfile.write_text("\n".join(lines) + "\n", encoding="utf-8")
    try:
        base = [PY, "-m", "modal", "secret", "create", "koi-llm-api", "--from-dotenv", str(envfile)]
        rc, err = run(base + ["--force"])
        method = "create --force"
        if rc != 0:
            run([PY, "-m", "modal", "secret", "delete", "koi-llm-api"], stdin="y\n")
            rc, err = run(base)
            method = "delete + create"
        log("secret %s via %s: rc=%s %s" % (mode, method, rc, "" if rc == 0 else err.strip()[:150]))
        return rc == 0
    finally:
        try:
            envfile.unlink()
        except OSError:
            pass

def restore():
    for _ in range(3):
        if swap("good"):
            return True
        time.sleep(5)
    log("RESTORE FAILED - run: python agent_tasks\\acceptance\\fallback_live.py restore")
    return False

def token():
    tf = Path(tempfile.gettempdir()) / "koi_fb_tok.txt"
    run([PY, str(ROOT / "deploy" / "modal" / "tools" / "get_anon_token.py"), key("firebase_web_api_key.txt"), "--token-file", str(tf)])
    t = tf.read_text(encoding="utf-8").strip()
    tf.unlink()
    return t

CASES = [("normal_1", "I have a quiz tomorrow", "none"),
         ("handoff", "My dog passed away today", "none"),
         ("exercise", "can we do a breathing exercise", "start_breathing")]

def check(label, cases):
    tok = token()
    for name, msg, ev in cases:
        body = {"message": msg, "session_history": [], "client_event": ev}
        req = urllib.request.Request(URL + "/api/v1/chat", data=json.dumps(body).encode(), method="POST",
            headers={"Authorization": "Bearer " + tok, "Content-Type": "application/json", "Accept": "text/event-stream"})
        t0 = time.time()
        try:
            r = opener.open(req, timeout=300)
        except urllib.error.HTTPError as e:
            log("%s %s HTTP %d" % (label, name, e.code)); continue
        except Exception as e:
            log("%s %s exception %s" % (label, name, type(e).__name__)); continue
        names, first, done, evn = [], None, {}, None
        for raw in r:
            line = raw.decode("utf-8").rstrip("\r\n")
            if line.startswith("event:"):
                evn = line[6:].strip()
            elif line.startswith("data:"):
                if first is None:
                    first = time.time() - t0
                names.append(evn)
                if evn == "done":
                    try:
                        done = json.loads(line[5:].strip())
                    except ValueError:
                        done = {}
        risk = done.get("risk") or {}
        log("%s %-8s first_event=%.1fs total=%.1fs backend=%s fallback=%s handoff=%s ui=%s deltas=%d risk=%s" % (
            label, name, first if first is not None else -1, time.time() - t0, done.get("reply_backend"),
            done.get("reply_fallback_reason"), bool(done.get("handoff")),
            [a.get("name") for a in done.get("ui_actions", [])], names.count("delta"),
            risk.get("risk_category", risk.get("status"))))
        time.sleep(3)

def wait(seconds, why):
    log("waiting %ds (%s). Send NO chat requests meanwhile." % (seconds, why))
    end = time.time() + seconds
    while time.time() < end:
        time.sleep(min(60, max(1, end - time.time())))
        log("  %ds left" % max(0, int(end - time.time())))

def main():
    if len(sys.argv) > 1 and sys.argv[1] == "restore":
        sys.exit(0 if restore() else 1)
    log("start: both provider keys will be replaced with invalid values")
    if not swap("broken"):
        restore()
        return
    try:
        wait(330, "let the running chat container scale down")
        check("BOTH_BROKEN", CASES)
    finally:
        restore()
    wait(330, "let the broken-key container scale down")
    check("AFTER_RESTORE", CASES[:1])
    log("done. expected: BOTH_BROKEN normal_1 and handoff -> backend=local fallback=http_4xx|http_4xx; exercise -> local; AFTER_RESTORE -> backend=api")

main()