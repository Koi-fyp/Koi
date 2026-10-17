"""G0b repro: CHARACTERISE the current chat_core + director behaviour in memory. Asserts nothing about desired behaviour.

Harness: the same as deploy/modal/test_reply_backend.py: build_app(fake engine, fake tokenizer, fake verify,
sampling lambda, {"crisis_client": FakeCrisisClient(result, delay)}) through httpx.ASGITransport. No network, no Modal,
no model, no secrets: the director secret is a local dummy value. KOI_DEBUG_TRACE=1 is set in-process so the
director's own reasons show in state.trace. Nothing is written to disk.

Usage (koivenv, cmd):  set PYTHONDONTWRITEBYTECODE=1 & python -B agent_tasks\\acceptance\\g0b_repro.py
Sections: (a) late risk, (b) failed start_* turns, (c) malformed requests. Exit 0 always.
"""
import asyncio
import json
import os
import sys
import time

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
ENGINE_ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ENGINE_ROOT, "deploy", "modal"))
sys.path.insert(0, os.path.join(ENGINE_ROOT, "koi_policy"))

import httpx  # noqa: E402

from chat_core import FALLBACK_REPLY, build_app  # noqa: E402
from crisis_client import FakeCrisisClient  # noqa: E402
import director  # noqa: E402  (the same module object chat_core imports from sys.path)

LOCAL_REPLY = "I am here."
LOW = {"status": "ok", "risk_category": "LOW", "crisis_score": 0.1}
HIGH = {"status": "ok", "risk_category": "HIGH", "crisis_score": 0.95}
UNAVAILABLE = {"status": "unavailable"}
REVIEWED = {s for j in director.J.values() for st in j["steps"].values()
            for s in ((st.get("say") or {}).values() if isinstance(st.get("say"), dict) else [])}


class Engine:
    """Companion turns: valid JSON reply. Director phrase turns (request id 'phrase-...'): plain text, or raise."""
    def __init__(self, phrase_raises=False):
        self.phrase_raises = phrase_raises

    async def generate(self, prompt, params, request_id):
        if str(request_id).startswith("phrase-"):
            if self.phrase_raises:
                raise RuntimeError("phrase generation failed (stub)")
            yield _Out("Thank you for telling me.")
            return
        yield _Out('{"companion_state":{"emotion":"neutral","intensity":0.3},"reply":"%s"}' % LOCAL_REPLY)


class _Out:
    def __init__(self, text):
        self.outputs = [type("C", (), {"text": text})()]


class Tok:
    def apply_chat_template(self, messages, **kw):
        return str(messages)

    def __call__(self, prompt, **kw):
        return {"input_ids": list(prompt)}


class Env:
    def __init__(self, **values):
        self.values, self.old = values, {}

    def __enter__(self):
        for k, v in self.values.items():
            self.old[k] = os.environ.get(k)
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v

    def __exit__(self, *exc):
        for k, v in self.old.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v


BASE_ENV = {"KOI_EXERCISES": "1", "KOI_DIRECTOR_SECRET": "g0b-local-dummy", "KOI_DEBUG_TRACE": "1",
            "KOI_REPLY_BACKEND": None, "KOI_API_ON_HANDOFF": None}


def call(*, json_body=None, files=None, data=None, content=None, headers=None, risk=LOW, delay=0.0,
         engine=None, env=None, auth=True):
    """One request. Returns dict(status, events, detail, app_exception, seconds)."""
    errors = []
    app = build_app(engine or Engine(), Tok(), lambda token: {"sub": "uid-g0b"}, lambda schema, **kw: kw,
                    {"crisis_client": FakeCrisisClient(dict(risk), delay=delay)})

    async def guarded(scope, receive, send):          # records the class of any exception that escapes the app
        try:
            await app(scope, receive, send)
        except Exception as exc:  # noqa: BLE001
            errors.append(type(exc).__name__ + ": " + str(exc)[:90])
            raise

    async def go():
        transport = httpx.ASGITransport(app=guarded, raise_app_exceptions=False)
        async with httpx.AsyncClient(transport=transport, base_url="http://test", timeout=30) as http:
            h = dict(headers or {})
            if auth:
                h["Authorization"] = "Bearer g0b"
            kw = {"headers": h}
            if files is not None:
                kw["files"] = files
                if data is not None:
                    kw["data"] = data
            elif content is not None:
                kw["content"] = content
            else:
                kw["json"] = json_body
            return await http.post("/api/v1/chat", **kw)

    t0 = time.monotonic()
    with Env(**{**BASE_ENV, **(env or {})}):
        resp = asyncio.run(go())
    out = {"status": resp.status_code, "seconds": round(time.monotonic() - t0, 2), "app_exception": errors[0] if errors else None}
    if resp.headers.get("content-type", "").startswith("text/event-stream"):
        out["events"] = [(f.split("\n", 1)[0][7:], json.loads(f.split("data: ", 1)[1]))
                         for f in resp.text.split("\n\n") if f.startswith("event: ") and "data: " in f]
    else:
        try:
            out["detail"] = resp.json().get("detail")
        except Exception:  # noqa: BLE001
            out["detail"] = resp.text[:80]
    return out


def ev(r, name):
    return [d for n, d in r.get("events", []) if n == name]


def token_of(r):
    s = ev(r, "state")
    return s[-1].get("exercise_state") if s else None


def text_source(r):
    deltas = [d.get("text", "") for d in ev(r, "delta")]
    joined = "".join(deltas).strip()
    if not deltas:
        return "none"
    if joined == LOCAL_REPLY:
        return "companion model (normal_events; stub reply)"
    if joined == FALLBACK_REPLY:
        return "FALLBACK_REPLY"
    if any(s in joined for s in REVIEWED) or len(deltas) >= 2:
        return "director sentences (ack + reviewed journey lines)"
    return "other"


def show(label, r, extra=""):
    names = [n for n, _ in r.get("events", [])]
    risk = (ev(r, "risk") or [{}])[0]
    ho = ev(r, "handoff")
    ui = [u.get("name") for u in ev(r, "ui_action")]
    st = ev(r, "state")
    why = (st[-1].get("trace") if st else None) or []
    print("\n[%s] HTTP %s  %.2fs%s" % (label, r["status"], r["seconds"], ("  " + extra) if extra else ""))
    if r.get("app_exception"):
        print("   app exception: %s" % r["app_exception"])
    if "detail" in r:
        print("   error detail: %s" % (json.dumps(r["detail"])[:160]))
    if names:
        print("   events: %s" % " ".join(names))
        print("   risk: %s %s | handoff: %s | ui_actions: %s" % (risk.get("status"), risk.get("risk_category"),
                                                              ho[0] if ho else None, ui))
        print("   reply source: %s | text: %r" % (text_source(r), "".join(d.get("text", "") for d in ev(r, "delta"))[:110]))
        if why:
            print("   director trace: %s" % " / ".join(why)[:300])


def section_a():
    print("\n=================== (a) LATE RISK: score arrives after the director ran ===================")
    show("a1 control: plain turn, HIGH immediately", call(json_body={"message": "hello"}, risk=HIGH))
    show("a2 plain turn, HIGH after 1.5 s (director waits 1.0 s)", call(json_body={"message": "hello"}, risk=HIGH, delay=1.5))
    show("a3 start_breathing, HIGH after 3.5 s (director waits 3.0 s)",
         call(json_body={"message": "can we do a breathing exercise", "client_event": "start_breathing"},
              risk=HIGH, delay=3.5))
    start = call(json_body={"message": "can we do a breathing exercise", "client_event": "start_breathing"}, risk=LOW)
    tok = token_of(start)
    show("a4 mid-playback text with exercise_state, HIGH after 3.5 s",
         call(json_body={"message": "my chest feels tight", "exercise_state": tok}, risk=HIGH, delay=3.5),
         "(token from a LOW start_breathing turn)")
    show("a4b control: same, HIGH immediately",
         call(json_body={"message": "my chest feels tight", "exercise_state": tok}, risk=HIGH))
    show("a5 audio-only, transcript arrives after 3.5 s (audio wait 3.0 s)",
         call(files={"payload": (None, json.dumps({"session_history": []})), "audio": ("a.wav", b"RIFF-stub", "audio/wav")},
              risk={**LOW, "transcript": "hello there", "language": "en"}, delay=3.5))
    show("a5b control: audio-only, transcript immediately",
         call(files={"payload": (None, json.dumps({"session_history": []})), "audio": ("a.wav", b"RIFF-stub", "audio/wav")},
              risk={**LOW, "transcript": "hello there", "language": "en"}))
    show("a6 plain turn, HIGH after 6 s (beyond the 5 s cap)", call(json_body={"message": "hello"}, risk=HIGH, delay=6.0))


def section_b():
    print("\n=================== (b) FAILED start_* TURNS ===================")
    for ev_name, msg in (("start_breathing", "can we do a breathing exercise"), ("start_grounding", "grounding please"),
                         ("start_plan", "make a plan")):
        show("b-%s control (LOW)" % ev_name, call(json_body={"message": msg, "client_event": ev_name}, risk=LOW))
        show("b-%s crisis UNAVAILABLE" % ev_name, call(json_body={"message": msg, "client_event": ev_name}, risk=UNAVAILABLE))
    show("b-start_breathing crisis scorer TIMEOUT (4 s > 3 s wait)",
         call(json_body={"message": "can we do a breathing exercise", "client_event": "start_breathing"}, risk=LOW, delay=4.0))
    real = director.handle_turn
    director.handle_turn = lambda *a, **k: (_ for _ in ()).throw(RuntimeError("director failed (stub)"))
    try:
        show("b-director raises", call(json_body={"message": "can we do a breathing exercise",
                                                  "client_event": "start_breathing"}, risk=LOW))
    finally:
        director.handle_turn = real
    show("b-ack phrase generation raises", call(json_body={"message": "can we do a breathing exercise",
                                                           "client_event": "start_breathing"},
                                                risk=LOW, engine=Engine(phrase_raises=True)))
    show("b-director secret missing", call(json_body={"message": "can we do a breathing exercise",
                                                      "client_event": "start_breathing"},
                                           risk=LOW, env={"KOI_DIRECTOR_SECRET": None}))


def section_c():
    print("\n=================== (c) MALFORMED REQUESTS (expected 422; any 500 is reported) ===================")
    crisis_tok = token_of(call(json_body={"message": "hello"}, risk=HIGH))
    mp = lambda payload, **media: {"payload": (None, payload), **media}  # noqa: E731
    audio = ("a.wav", b"RIFF-stub", "audio/wav")
    video = ("v.mp4", b"mp4-stub", "video/mp4")
    cases = [
        ("bad role", dict(json_body={"message": "hi", "session_history": [{"role": "system", "content": "x"}]})),
        ("message is a number", dict(json_body={"message": 123})),
        ("session_history is a string", dict(json_body={"message": "hi", "session_history": "abc"})),
        ("exercise_state is a number", dict(json_body={"message": "hi", "exercise_state": 5})),
        ("message over 4000 chars", dict(json_body={"message": "a" * 4001})),
        ("empty message", dict(json_body={"message": ""})),
        ("no message field", dict(json_body={"session_history": []})),
        ("body is not JSON", dict(content=b"{not json", headers={"Content-Type": "application/json"})),
        ("corrupt multipart", dict(content=b"garbage-without-boundaries",
                                   headers={"Content-Type": "multipart/form-data; boundary=XYZ"})),
        ("multipart without payload", dict(files={"audio": audio})),
        ("multipart payload not JSON", dict(files=mp("{oops"))),
        ("multipart text only (no media)", dict(files=mp(json.dumps({"message": "hi"})))),
        ("multipart nothing usable", dict(files=mp(json.dumps({})))),
        ("text+audio (not allowed)", dict(files=mp(json.dumps({"message": "hi"}), audio=audio))),
        ("video only (not allowed)", dict(files=mp(json.dumps({}), video=video))),
        ("text+audio+video (not allowed)", dict(files=mp(json.dumps({"message": "hi"}), audio=audio, video=video))),
        ("audio over 25 MiB", dict(files=mp(json.dumps({}), audio=("big.wav", b"\0" * (25 * 1024 * 1024 + 1), "audio/wav")))),
        ("video over 80 MiB", dict(files=mp(json.dumps({"message": "hi"}),
                                            video=("big.mp4", b"\0" * (80 * 1024 * 1024 + 1), "video/mp4")))),
        ("unknown client_event (exercises ON)", dict(json_body={"message": "hi", "client_event": "start_dancing"})),
        ("unknown client_event (exercises OFF)", dict(json_body={"message": "hi", "client_event": "start_dancing"},
                                                      env={"KOI_EXERCISES": "0"})),
        ("invalid crisis_path, fresh state, LOW", dict(json_body={"message": "hi", "policy_event": "crisis_resolved",
                                                                  "crisis_path": "bogus"})),
        ("invalid crisis_path, crisis-mode token, LOW", dict(json_body={"message": "hi", "exercise_state": crisis_tok,
                                                                        "policy_event": "crisis_resolved",
                                                                        "crisis_path": "bogus"})),
        ("crisis_resolved without crisis_path, crisis token, LOW",
         dict(json_body={"message": "hi", "exercise_state": crisis_tok, "policy_event": "crisis_resolved"})),
        ("unknown policy_event, crisis token, LOW", dict(json_body={"message": "hi", "exercise_state": crisis_tok,
                                                                    "policy_event": "foo"})),
        ("invalid crisis_path, crisis token, HIGH (on_risk path)",
         dict(json_body={"message": "hi", "exercise_state": crisis_tok, "policy_event": "crisis_resolved",
                         "crisis_path": "bogus"}, risk=HIGH)),
        ("tampered exercise_state (control)", dict(json_body={"message": "hi", "exercise_state": (crisis_tok or "x.y")[:-1] + "0"})),
        ("no Authorization header", dict(json_body={"message": "hi"}, auth=False)),
    ]
    rows = []
    for label, kw in cases:
        r = call(**kw)
        names = [n for n, _ in r.get("events", [])]
        cls = r.get("app_exception") or (json.dumps(r.get("detail"))[:100] if "detail" in r else
                                          ("stream ok: " + " ".join(names[-2:])))
        rows.append((label, r["status"], cls))
        print("  %-58s HTTP %s  %s" % (label, r["status"], cls))
    bad = [x for x in rows if x[1] >= 500]
    print("\n  5xx responses: %d of %d%s" % (len(bad), len(rows), "".join("\n    - %s: %s" % (l, c) for l, _, c in bad)))


if __name__ == "__main__":
    try:
        section_a()
        section_b()
        section_c()
    except Exception:  # noqa: BLE001 - a harness error is reported, never hidden
        import traceback
        traceback.print_exc()
    sys.exit(0)
