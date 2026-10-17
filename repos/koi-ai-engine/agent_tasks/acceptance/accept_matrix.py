"""KOI chat acceptance matrix (stdlib only; acceptance kit, Work Package A). Reads the deployed service, changes nothing.

Usage (koivenv, cmd):
    set PYTHONDONTWRITEBYTECODE=1
    python agent_tasks\\acceptance\\accept_matrix.py <CHAT_URL> [--dry-run]

Token: env KOI_TOKEN only. It is never printed and never written. --dry-run prints the plan and sends nothing.
Budget: at most MAX_REQUESTS chat requests, SLEEP_S between them, synthetic messages only. Every request goes to the
hosted providers when the chat app was deployed with KOI_REPLY_BACKEND=api (see RUNBOOK.txt quota warning).

Per request it prints: event names in order, risk status/category/score, handoff present (+reason), ui_action names
and args, urgent ui_action (sent before companion_state), exercise_state present (bool) + first 10 chars,
reply_backend, reply_fallback_reason, done.full_text == "".join(deltas), latency_ms, time to first event, total time.
Never printed or stored: the token, any `trace`, a full exercise_state. Reply text is stored truncated (120 chars).
Writes agent_tasks/reports/acceptance/accept_matrix_<stamp>.json and .md. Exit 0 always (a report, not a gate).

Expected behaviour is taken from the code at commit c172d35 (see RUNBOOK.txt / the acceptance report for file:line):
  - start_* turn waits <= 3 s for the server's own crisis score, a plain turn <= 1 s (chat_core.py:348-352). If the
    score is not back in time, the director gets tier None and starts nothing (director.py:340-341).
  - a tampered exercise_state is silently replaced by a fresh state (director.py:258-262); tokens never expire and an
    older valid token can be replayed (state_token.py:6-9).
  - crisis mode lasts until policy_event crisis_resolved + crisis_path (policy.py:135-152); any later HIGH reopens it
    (policy.py:19, R1). If the server's own tier is HIGH and exercise_state is sent, chat_core routes to
    director.on_risk, which does not receive policy_event (chat_core.py:403-407, director.py:377-383).
"""
import base64
import json
import os
import sys
import time

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cold_start_probe import _safe, request_following, sse_events  # noqa: E402

MAX_REQUESTS = 25
SLEEP_S = 3
HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "reports", "acceptance"))

# Synthetic messages. Categories observed on the live service Oct 17 (agent_tasks/reports/chat_sessions); the crisis
# model is an emotion proxy, so the category of any text is NOT guaranteed and is always recorded as observed.
MSG_CHAT = "hey, what's up?"
MSG_START = "can we do a breathing exercise"
MSG_LOW = "I am so excited about my presentation tomorrow"          # LOW x3 on Oct 17
MSG_MODERATE = "Im not angry, Im nervous"                           # MODERATE x1 on Oct 17
MSG_HIGH = ["Im nervous before my presentation",                    # HIGH x16 on Oct 17
            "I feel lonely tonight", "My dog passed away today"]
MSG_DONE = "done"
MSG_STOP = "stop"
MSG_PAUSE = "hold on, someone is at the door"
MSG_STOPPED = "I stopped it"
MSG_RESOLVE = "It was a misunderstanding, I am fine."
BREATHING_ARGS = {"pattern": "slow_6_per_min", "inhale_s": 4, "exhale_s": 6, "cycles": 6,
                  "cue_audio": ["Breathe in", "Breathe out"]}


def _prefix(token):
    return token[:10] if isinstance(token, str) else None


def _peek(token):
    """Read-only summary of the signed state body (base64 JSON, not encrypted): mode / journey / step / playing.
    Test-harness only; clients must never parse the token. The token itself is never printed or stored."""
    try:
        body = token.split(".")[0]
        p = json.loads(base64.urlsafe_b64decode(body + "=" * (-len(body) % 4)))
        ex = p.get("ex") or {}
        return {"rev": p.get("rev"), "mode": (p.get("policy") or {}).get("mode"), "journey": ex.get("j"),
                "step": ex.get("step"), "playing": ex.get("playing")}
    except Exception:  # noqa: BLE001
        return None


def _rk(row):
    return row.get("risk") or {}


def tamper(token):
    """Flip the last hex char of the HMAC: still well-formed, signature invalid."""
    last = token[-1]
    return token[:-1] + ("0" if last != "0" else "1")


class Budget(Exception):
    pass


class Runner:
    def __init__(self, base, token, dry_run=False):
        self.base = base.rstrip("/")
        self._token = token
        self.dry_run = dry_run
        self.sent = 0
        self.rows = []

    def turn(self, case, step, message, *, history=None, exercise_state=None, client_event="none",
             policy_event=None, crisis_path=None, state_note=None, expect=""):
        """One POST /api/v1/chat. Returns (row, full_exercise_state_or_None, full_text). Only `row` is reported."""
        if self.sent >= MAX_REQUESTS:
            raise Budget("request budget %d reached" % MAX_REQUESTS)
        payload = {"message": message, "session_history": list(history or []), "exercise_state": exercise_state,
                   "client_event": client_event}
        if policy_event:
            payload.update(policy_event=policy_event, crisis_path=crisis_path)
        row = {"case": case, "step": step, "expect": expect,
               "request": {"message": message, "client_event": client_event, "policy_event": policy_event,
                           "crisis_path": crisis_path, "history_turns": len(payload["session_history"]),
                           "exercise_state_sent": state_note or (("prefix " + _prefix(exercise_state))
                                                                 if exercise_state else None)}}
        print("\n[%02d] %s / %s" % (self.sent + 1, case, step))
        print("  request: message=%r client_event=%s policy_event=%s crisis_path=%s exercise_state=%s" % (
            message, client_event, policy_event, crisis_path, row["request"]["exercise_state_sent"]))
        if self.dry_run:
            self.sent += 1
            row["dry_run"] = True
            self.rows.append(row)
            return row, None, ""
        if self.sent:
            time.sleep(SLEEP_S)
        self.sent += 1
        names, events, first_s = [], [], None
        t_start = time.monotonic()
        try:
            resp, conn, hops, t0 = request_following(
                "POST", self.base + "/api/v1/chat", body=json.dumps(payload).encode("utf-8"),
                headers={"Authorization": "Bearer " + self._token, "Content-Type": "application/json",
                         "Accept": "text/event-stream"}, label="   ")
            row["hops"] = hops
            row["http_status"] = resp.status
            if resp.status != 200:
                row["error_body"] = resp.read()[:200].decode("utf-8", "replace")
                conn.close()
                print("  HTTP %d %s" % (resp.status, row["error_body"]))
                self.rows.append(row)
                return row, None, ""
            for name, data in sse_events(resp):
                if first_s is None:
                    first_s = time.monotonic() - t0
                names.append(name)
                events.append((name, data))
            conn.close()
        except Exception as exc:  # noqa: BLE001 - recorded, matrix continues
            row["error"] = "%s: %s" % (type(exc).__name__, str(exc)[:160])
            print("  ERROR " + row["error"])
            self.rows.append(row)
            return row, None, ""
        total_s = time.monotonic() - t_start
        state_token, full_text = self._summarise(row, names, events, first_s, total_s)
        self._print(row)
        self.rows.append(row)
        return row, state_token, full_text

    @staticmethod
    def _summarise(row, names, events, first_s, total_s):
        def first(name):
            return next((d for n, d in events if n == name), None)
        risk = first("risk") or {}
        done = first("done") or {}
        handoff = first("handoff")
        cs_index = names.index("companion_state") if "companion_state" in names else len(names)
        ui = [{"name": d.get("name"), "args": d.get("args")} for n, d in events if n == "ui_action" and isinstance(d, dict)]
        urgent = [d.get("name") for i, (n, d) in enumerate(events)
                  if n == "ui_action" and i < cs_index and isinstance(d, dict)]
        deltas = [d.get("text", "") for n, d in events if n == "delta" and isinstance(d, dict)]
        state_ev = first("state") or {}
        token = done.get("exercise_state") if isinstance(done.get("exercise_state"), str) else state_ev.get("exercise_state")
        token = token if isinstance(token, str) else None
        full_text = done.get("full_text", "")
        row.update({
            "events": names,
            "risk": {"status": risk.get("status"), "category": risk.get("risk_category"),
                     "score": risk.get("crisis_score")},
            "handoff": bool(handoff), "handoff_reason": (handoff or {}).get("reason"),
            "ui_actions": ui, "urgent_ui": urgent,
            "exercise_state_present": token is not None, "exercise_state_prefix": _prefix(token),
            "state_summary": _peek(token) if token else None,
            "reply_backend": done.get("reply_backend"), "reply_fallback_reason": done.get("reply_fallback_reason"),
            "full_text_equals_deltas": bool(done) and full_text == "".join(deltas),
            "n_deltas": len(deltas), "reply_preview": full_text[:120],
            "latency_ms": (first("latency") or {}).get("latency_ms"),
            "first_event_s": round(first_s, 2) if first_s is not None else None, "total_s": round(total_s, 2),
            "done_present": bool(done),
            "trace_present": any(isinstance(d, dict) and "trace" in d for n, d in events if n in ("done", "state")),
            "checks": {
                "companion_state_before_delta": "delta" not in names or cs_index < names.index("delta"),
                "risk_exactly_once": names.count("risk") == 1,
                "state_immediately_before_done": len(names) >= 2 and names[-1] == "done" and names[-2] == "state",
                "done_risk_equals_streamed": done.get("risk") == (first("risk") or None),
            },
        })
        return token, full_text

    @staticmethod
    def _print(row):
        r = row["risk"]
        print("  events: %s" % " ".join(row["events"]))
        print("  risk: status=%s category=%s score=%s" % (r["status"], r["category"], r["score"]))
        print("  handoff=%s%s  urgent_ui=%s" % (row["handoff"], (" (%s)" % row["handoff_reason"]) if row["handoff"] else "",
                                               row["urgent_ui"]))
        for u in row["ui_actions"]:
            print("  ui_action %s %s" % (u["name"], json.dumps(u["args"], ensure_ascii=False)))
        print("  exercise_state present=%s prefix=%s state=%s" % (
            row["exercise_state_present"], row["exercise_state_prefix"], json.dumps(row["state_summary"])))
        print("  reply_backend=%s reply_fallback_reason=%s full_text==deltas=%s n_deltas=%d" % (
            row["reply_backend"], row["reply_fallback_reason"], row["full_text_equals_deltas"], row["n_deltas"]))
        print("  latency_ms=%s first_event_s=%s total_s=%s trace_present=%s checks=%s" % (
            row["latency_ms"], row["first_event_s"], row["total_s"], row["trace_present"],
            ",".join(k for k, v in row["checks"].items() if not v) or "all ok"))
        print("  reply: %r" % row["reply_preview"])


def _ui_names(row):
    return [u["name"] for u in row.get("ui_actions", [])]


def _high(row):
    return row.get("risk", {}).get("category") in ("HIGH", "CRITICAL")


def _verdict(row, ok, why_fail="", inconclusive=None):
    if "error" in row or row.get("http_status", 200) != 200:
        row["verdict"], row["note"] = "ERROR", row.get("error") or row.get("error_body", "")
    elif inconclusive:
        row["verdict"], row["note"] = "INCONCLUSIVE", inconclusive
    else:
        row["verdict"], row["note"] = ("PASS", "") if ok else ("FAIL", why_fail)
    print("  VERDICT %s %s" % (row["verdict"], row["note"]))


def hist(h, user, assistant):
    return h + [{"role": "user", "content": user}, {"role": "assistant", "content": assistant}]


def run(r):
    findings = []

    # U0 FIRST, so a cold crisis container shows the fail-closed path (start_* waits only 3 s for the score).
    row, _, _ = r.turn("U0_unavailable_probe", "start_breathing as the very first request", MSG_START,
                       client_event="start_breathing",
                       expect="risk unavailable -> no start_breathing, no handoff; risk ok non-crisis -> start_breathing")
    if not row.get("dry_run"):
        if row.get("risk", {}).get("status") == "unavailable":
            _verdict(row, "start_breathing" not in _ui_names(row) and not row.get("handoff"),
                     "exercise started or handoff sent although risk was unavailable")
        else:
            _verdict(row, True, inconclusive="risk was %s, unavailable path not reproduced (crisis warm?)"
                     % row.get("risk", {}).get("status"))

    row, _, _ = r.turn("N1_normal_chat", "plain chat", MSG_CHAT,
                       expect=">=1 delta, no ui_action, no handoff, state null, full_text == deltas")
    if not row.get("dry_run"):
        _verdict(row, row.get("n_deltas", 0) >= 1 and not row.get("ui_actions") and not row.get("handoff")
                 and not row.get("exercise_state_present") and row.get("full_text_equals_deltas")
                 and all(row["checks"].values()), "see fields", inconclusive=("risk HIGH: handoff expected instead"
                                                                              if _high(row) else None))

    # L2 start (expected LOW tier) -> P3 playback_done with the echoed token -> X4 tampered -> R5 replay
    row, t_play, txt = r.turn("L2_start_low", "client_event start_breathing", MSG_START, client_event="start_breathing",
                              expect="ui_action start_breathing with %s (+minutes_note); >=2 deltas; exercise_state"
                              % json.dumps(BREATHING_ARGS))
    h_play = hist([], MSG_START, txt)
    if not row.get("dry_run"):
        sb = next((u["args"] for u in row.get("ui_actions", []) if u["name"] == "start_breathing"), None)
        args_ok = isinstance(sb, dict) and all(sb.get(k) == v for k, v in BREATHING_ARGS.items())
        _verdict(row, args_ok and row.get("exercise_state_present") and row.get("n_deltas", 0) >= 2,
                 "start_breathing missing or args differ: %s" % json.dumps(sb, ensure_ascii=False),
                 inconclusive=("risk %s/%s: no exercise expected" % (_rk(row).get("status"), _rk(row).get("category")))
                 if _high(row) or _rk(row).get("status") != "ok" else None)
    if t_play or r.dry_run:
        row, _, _ = r.turn("P3_playback_done", "echo the signed token from L2", MSG_DONE, history=h_play,
                           exercise_state=t_play, client_event="playback_done",
                           expect="no start_breathing; post-check sentence(s); new exercise_state; no handoff")
        p3_row = row
        if not row.get("dry_run"):
            _verdict(row, "start_breathing" not in _ui_names(row) and row.get("exercise_state_present")
                     and row.get("n_deltas", 0) >= 1 and not row.get("handoff"), "see fields",
                     inconclusive="risk HIGH -> on_risk crisis path" if _high(row) else None)
        row, _, _ = r.turn("X4_tampered_token", "L2 token with one MAC char flipped", MSG_DONE, history=h_play,
                           exercise_state=tamper(t_play) if t_play else None, client_event="playback_done",
                           state_note="tampered (L2 token, last MAC char flipped)",
                           expect="HTTP 200, silent reset to a fresh state: no post-check, ordinary reply, new token")
        if not row.get("dry_run"):
            p3_step = (p3_row.get("state_summary") or {}).get("step")
            x4_step = (row.get("state_summary") or {}).get("step")
            _verdict(row, row.get("http_status") == 200 and row.get("exercise_state_present") and x4_step != p3_step,
                     "tampered token was honoured: step %r == P3 step %r" % (x4_step, p3_step),
                     inconclusive=None if p3_step else "P3 reached no exercise step; nothing to compare")
            if row.get("verdict") == "PASS":
                findings.append("X4: a tampered exercise_state is reset SILENTLY (no event tells the client; "
                                "trace is off); tokens carry no expiry (state_token.py has no exp field).")
        row, _, _ = r.turn("R5_replay_token", "L2 token sent AGAIN after P3 consumed it", MSG_DONE, history=h_play,
                           exercise_state=t_play, client_event="playback_done", state_note="replay of L2 token",
                           expect="accepted (replay is a disclosed limitation, state_token.py:6-9): same as P3")
        if not row.get("dry_run"):
            _verdict(row, True, inconclusive="recorded only: replay acceptance is by design")

    # M6 start at (expected) MODERATE -> S7 "stop" interruption
    row, t_play2, txt2 = r.turn("M6_start_moderate", "client_event start_breathing, MODERATE-ish text", MSG_MODERATE,
                                client_event="start_breathing",
                                expect="MODERATE/LOW: start_breathing; HIGH: crisis handoff, no exercise")
    if not row.get("dry_run"):
        started = "start_breathing" in _ui_names(row)
        _verdict(row, (started and not _high(row)) or (not started and _high(row) and row.get("handoff")),
                 "tier %s but started=%s handoff=%s" % (_rk(row).get("category"), started, row.get("handoff")),
                 inconclusive="risk %s" % _rk(row).get("status") if row.get("risk", {}).get("status") != "ok" else None)
    stop_token = t_play2 if t_play2 and "start_breathing" in _ui_names(row) else t_play
    row, _, _ = r.turn("S7_interrupt_stop", "text 'stop' mid-playback", MSG_STOP,
                       history=hist([], MSG_MODERATE, txt2) if stop_token is t_play2 else h_play,
                       exercise_state=stop_token,
                       state_note=None if stop_token is t_play2 else "replay of L2 token (M6 did not start)",
                       expect="urgent ui_action stop_breathing BEFORE companion_state; 'stopped' line; token")
    if not row.get("dry_run"):
        _verdict(row, "stop_breathing" in row.get("urgent_ui", []), "no urgent stop_breathing")

    # PA8 fresh start -> pause by unrelated text mid-playback
    row, t_play3, txt3 = r.turn("PA8a_start", "client_event start_breathing", MSG_START, client_event="start_breathing",
                                expect="start_breathing")
    row, _, _ = r.turn("PA8b_interrupt_pause", "unrelated text mid-playback", MSG_PAUSE,
                       history=hist([], MSG_START, txt3), exercise_state=t_play3 or t_play,
                       expect="urgent ui_action pause_breathing before companion_state")
    if not row.get("dry_run"):
        _verdict(row, "pause_breathing" in row.get("urgent_ui", []), "no urgent pause_breathing",
                 inconclusive="risk HIGH -> crisis stop instead" if _high(row) else None)
    row, _, _ = r.turn("PS9_playback_stopped", "client_event playback_stopped", MSG_STOPPED,
                       history=hist([], MSG_START, txt3), exercise_state=t_play3 or t_play,
                       client_event="playback_stopped", state_note="replay of PA8a token (still 'playing')",
                       expect="no urgent ui (client already stopped); 'stopped' step line; token")
    if not row.get("dry_run"):
        _verdict(row, not row.get("urgent_ui") and row.get("exercise_state_present"), "see fields",
                 inconclusive="risk HIGH -> crisis path" if _high(row) else None)

    # H10 HIGH -> C11 stays in crisis -> C12 crisis_resolved(misunderstanding) -> C13 benign -> C14 new HIGH
    t_crisis, high_msg, h = None, None, []
    for i, msg in enumerate(MSG_HIGH):
        row, tok, txt = r.turn("H10_high_handoff", "attempt %d" % (i + 1), msg,
                               expect="risk HIGH/CRITICAL -> handoff {to: crisis} in the SAME response")
        if row.get("dry_run"):
            t_crisis, high_msg, h = None, msg, hist([], msg, "")
            break
        if _high(row):
            _verdict(row, row.get("handoff"), "risk HIGH streamed but no handoff: the score missed the 1 s director "
                     "wait (chat_core.py:348-360) and was only picked up by the post-reply wait")
            high_msg = msg                                   # reused by C14 as the "new HIGH" text
            if not row.get("handoff"):
                findings.append("H10: HIGH risk event without a handoff (late score, see chat_core.py:348-360).")
                continue                                     # this token is NOT in crisis mode; try the next text
            t_crisis, h = tok, hist([], msg, txt)
            break
        else:
            _verdict(row, True, inconclusive="risk %s/%s, trying next HIGH candidate"
                     % (_rk(row).get("status"), _rk(row).get("category")))
    if high_msg and (t_crisis or r.dry_run):
        row, tok, txt = r.turn("C11_stay_in_crisis", "LOW text, no policy_event", MSG_LOW, history=h,
                               exercise_state=t_crisis, expect="handoff crisis repeats (R2 STAY_IN_CRISIS)")
        if not row.get("dry_run"):
            _verdict(row, row.get("handoff"), "crisis mode did not persist")
        h, t_crisis = hist(h, MSG_LOW, txt), tok or t_crisis
        t_resolved = None
        for i, msg in enumerate((MSG_RESOLVE, MSG_LOW)):
            row, tok, txt = r.turn("C12_crisis_resolved", "misunderstanding, attempt %d" % (i + 1), msg, history=h,
                                   exercise_state=t_crisis, policy_event="crisis_resolved",
                                   crisis_path="misunderstanding",
                                   expect="no handoff in this response (R2 EXIT_TO_CHAT) unless this text scores HIGH")
            if row.get("dry_run"):
                break
            h = hist(h, msg, txt)
            if not row.get("handoff"):
                _verdict(row, True)
                t_resolved = tok
                break
            why = ("with exercise_state + HIGH tier the server calls director.on_risk, which drops policy_event "
                   "(chat_core.py:403-407)" if _high(row) else "crisis_resolved NOT honoured at a non-HIGH tier: bug")
            _verdict(row, False, "handoff still present (risk %s/%s): %s"
                     % (_rk(row).get("status"), _rk(row).get("category"), why))
            findings.append("C12 attempt %d: crisis_resolved ignored, risk %s/%s."
                            % (i + 1, _rk(row).get("status"), _rk(row).get("category")))
            t_crisis = tok or t_crisis
        if t_resolved or r.dry_run:
            row, tok, txt = r.turn("C13_after_resolve", "benign text", MSG_LOW, history=h, exercise_state=t_resolved,
                                   expect="no handoff (mode chat) unless this text scores HIGH")
            if not row.get("dry_run"):
                _verdict(row, not row.get("handoff") or _high(row), "handoff without a HIGH score")
            h, t_after = hist(h, MSG_LOW, txt), tok or t_resolved
            row, tok, txt = r.turn("C14_new_high", "genuinely new HIGH after resolution", high_msg, history=h,
                                   exercise_state=t_after, expect="risk HIGH -> handoff re-triggers (R1)")
            if not row.get("dry_run"):
                _verdict(row, row.get("handoff") if _high(row) else True,
                         "HIGH again but no handoff", inconclusive=None if _high(row)
                         else "risk %s: re-trigger not exercised" % _rk(row).get("category"))
                row["handoff_retriggered"] = bool(row.get("handoff"))
            h = hist(h, high_msg, txt)
            if (tok and row.get("handoff")) or r.dry_run:
                row, tok2, txt = r.turn("C15_resolve_while_high", "crisis_resolved sent with a HIGH-scoring message",
                                        high_msg, history=h, exercise_state=tok, policy_event="crisis_resolved",
                                        crisis_path="misunderstanding",
                                        expect="per code: if tier HIGH, policy_event is dropped -> handoff stays")
                if not row.get("dry_run"):
                    _verdict(row, True, inconclusive="recorded: handoff=%s risk=%s"
                             % (row.get("handoff"), _rk(row).get("category")))
                    if row.get("handoff") and _high(row):
                        findings.append("C15: user who finished UX Flow 4 stays in crisis because the resolving "
                                        "message scored HIGH (policy_event never reaches policy.decide).")
                h = hist(h, high_msg, txt)
                row, _, _ = r.turn("C16_after_C15", "benign text, no policy_event", MSG_LOW, history=h,
                                   exercise_state=tok2 or tok,
                                   expect="if C15 was dropped: handoff crisis repeats (trap); else none")
                if not row.get("dry_run"):
                    _verdict(row, True, inconclusive="recorded: handoff=%s" % row.get("handoff"))
    return findings


def write_reports(r, findings, base, started):
    os.makedirs(OUT_DIR, exist_ok=True)
    stamp = time.strftime("%Y%m%d_%H%M%S")
    meta = {"target": _safe(base), "started": started, "finished": time.strftime("%Y-%m-%d %H:%M:%S"),
            "requests_sent": r.sent, "max_requests": MAX_REQUESTS, "sleep_s": SLEEP_S, "dry_run": r.dry_run,
            "verdicts": {v: sum(1 for x in r.rows if x.get("verdict") == v)
                         for v in ("PASS", "FAIL", "INCONCLUSIVE", "ERROR")},
            "reply_backends_seen": sorted({str(x.get("reply_backend")) for x in r.rows if "reply_backend" in x}),
            "findings": findings}
    jpath = os.path.join(OUT_DIR, "accept_matrix_%s.json" % stamp)
    with open(jpath, "w", encoding="utf-8") as f:
        json.dump({"meta": meta, "rows": r.rows}, f, ensure_ascii=False, indent=2)
    lines = ["# KOI chat acceptance matrix %s" % stamp, "",
             "Target `%s` · started %s · finished %s · requests %d/%d · sleep %ss%s" % (
                 meta["target"], started, meta["finished"], r.sent, MAX_REQUESTS, SLEEP_S,
                 " · DRY RUN (nothing sent)" if r.dry_run else ""),
             "", "Verdicts: " + ", ".join("%s %d" % kv for kv in meta["verdicts"].items()),
             "Reply backends seen: " + ", ".join(meta["reply_backends_seen"] or ["-"]), "",
             "| # | case | step | risk | handoff | ui_actions (urgent) | ex_state | backend / fallback | text==deltas | latency ms / total s | verdict |",
             "|---|---|---|---|---|---|---|---|---|---|---|"]
    for i, x in enumerate(r.rows, 1):
        rk = x.get("risk") or {}
        lines.append("| %d | %s | %s | %s %s %s | %s | %s%s | %s | %s / %s | %s | %s / %s | %s %s |" % (
            i, x["case"], x["step"], rk.get("status", "-"), rk.get("category") or "", rk.get("score") or "",
            "yes" if x.get("handoff") else "no", ", ".join(_ui_names(x)) or "-",
            (" (urgent: %s)" % ", ".join(x["urgent_ui"])) if x.get("urgent_ui") else "",
            ("yes (mode %s, %s.%s)" % ((x.get("state_summary") or {}).get("mode"),
                                       (x.get("state_summary") or {}).get("journey"),
                                       (x.get("state_summary") or {}).get("step")))
            if x.get("exercise_state_present") else "no", x.get("reply_backend", "-"),
            x.get("reply_fallback_reason") or "-", x.get("full_text_equals_deltas", "-"), x.get("latency_ms", "-"),
            x.get("total_s", "-"), x.get("verdict", "-"), (x.get("note") or "").replace("|", "/")))
    lines += ["", "## Event order per request", ""]
    for i, x in enumerate(r.rows, 1):
        lines.append("%d. `%s` %s" % (i, x["case"], " ".join(x.get("events", [])) or "(none)"))
    lines += ["", "## Expectations", ""] + ["- `%s`: %s" % (x["case"], x["expect"]) for x in r.rows]
    lines += ["", "## Auto findings", ""] + (["- " + f for f in findings] or ["- none"])
    mpath = os.path.join(OUT_DIR, "accept_matrix_%s.md" % stamp)
    with open(mpath, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print("\nwrote %s\nwrote %s" % (jpath, mpath))


def main(argv):
    if not argv or argv[0].startswith("-"):
        print(__doc__)
        return 0
    base, dry = argv[0], "--dry-run" in argv
    token = os.environ.get("KOI_TOKEN", "").strip()
    if not token and not dry:
        print("KOI_TOKEN is not set; nothing sent. (Use --dry-run to see the plan.)")
        return 0
    started = time.strftime("%Y-%m-%d %H:%M:%S")
    print("accept_matrix target=%s started=%s max_requests=%d sleep=%ss%s" % (
        _safe(base), started, MAX_REQUESTS, SLEEP_S, " DRY RUN" if dry else ""))
    r = Runner(base, token, dry_run=dry)
    token = None
    findings = []
    try:
        findings = run(r)
    except Budget as exc:
        print("STOP: %s" % exc)
        findings.append("matrix stopped early: %s" % exc)
    except KeyboardInterrupt:
        findings.append("matrix interrupted by the user")
    except Exception as exc:  # noqa: BLE001 - always write what was collected
        print("ABORT: %s" % type(exc).__name__)
        findings.append("matrix aborted by a harness error: %s at request %d" % (type(exc).__name__, r.sent))
    finally:
        r._token = None
        write_reports(r, findings, base, started)
    return 0


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    finally:
        sys.exit(0)
