"""Print the raw SSE events of ONE live exercise turn, exactly the request trace_check.py sends.

Usage (Ahmad): set KOI_TOKEN in the same cmd window first (as smoke_only.bat requires), then
    E:\\Setups\\anaconda\\envs\\koivenv\\python.exe agent_tasks\\delta_probe.py <CHAT_URL> [--token-file PATH]
Token: KOI_TOKEN env or --token-file, the same as trace_check.py. The token is never printed or logged.
Reuses trace_check.py (its import raises urllib's 303 redirect limits to 200; requests use its 240 s timeout).
Always exits 0.
"""
import importlib.util
import json
import os
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent.parent / "deploy" / "modal" / "tools"


def _trace_check():
    spec = importlib.util.spec_from_file_location("trace_check", TOOLS / "trace_check.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)  # sets HTTPRedirectHandler.max_repeats / max_redirections = 200
    return module


def main(argv):
    if not argv:
        print(__doc__)
        return 0
    base = argv[0]
    token = os.environ.get("KOI_TOKEN", "")
    if "--token-file" in argv and argv.index("--token-file") + 1 < len(argv):
        with open(argv[argv.index("--token-file") + 1], encoding="utf-8") as handle:
            token = handle.read().strip()
    if not token:
        print("no token: set KOI_TOKEN or pass --token-file (same as trace_check.py)")
        return 0
    tc = _trace_check()
    print("request body: %s" % json.dumps({"session_history": [], **tc.EXERCISE}))
    print("timeout_s=%s max_repeats=%s max_redirections=%s" % (
        tc.TIMEOUT_S, tc._ur.HTTPRedirectHandler.max_repeats, tc._ur.HTTPRedirectHandler.max_redirections))
    try:
        events = tc.post_turn(base, token, tc.EXERCISE)
    except Exception as exc:  # HTTP error, timeout, bad SSE; never echo request headers
        print("request failed: %s %s" % (type(exc).__name__, getattr(exc, "code", "")))
        return 0
    deltas = []
    for i, (name, payload) in enumerate(events):
        if name == "delta":
            text = payload.get("text", "") if isinstance(payload, dict) else ""
            deltas.append(text)
            print("%2d %-15s delta#%d %r len=%d" % (i, name, len(deltas) - 1, text, len(text)))
        elif name == "ui_action":
            print("%2d %-15s name=%r" % (i, name, (payload or {}).get("name")))
        else:
            print("%2d %s" % (i, name))
    done = next((payload for name, payload in events if name == "done"), None)
    if not isinstance(done, dict):
        print("no done event")
        return 0
    print("done.full_text %r" % done.get("full_text"))
    print("done.full_text == ''.join(deltas): %s" % (done.get("full_text") == "".join(deltas)))
    print("done.exercise_state present: %s" % bool(done.get("exercise_state")))
    print("done keys: %s" % sorted(done))
    print("ui_action events: %s" % [p.get("name") for n, p in events if n == "ui_action" and isinstance(p, dict)])
    for name, payload in events:
        if name in ("done", "state") and isinstance(payload, dict) and "trace" in payload:
            print("%s.trace (first 200 chars): %s" % (name, json.dumps(payload["trace"], ensure_ascii=False)[:200]))
    if not any(name in ("done", "state") and isinstance(p, dict) and "trace" in p for name, p in events):
        print("trace: absent")
    return 0


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except Exception as exc:  # keep the promise: exit 0, no traceback with request details
        print("probe error: %s" % type(exc).__name__)
    sys.exit(0)
