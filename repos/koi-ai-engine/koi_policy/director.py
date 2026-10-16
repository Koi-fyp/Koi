"""
KOI exercise director: the hidden layer behind "the avatar just talks". Oct 15 2026. DRAFT by Claude.

The user only sees the companion talking in the main chat. Under the hood, each turn:
  1. verify the signed client-carried state (state_token.py; the engine stays stateless)
  2. distress pre-check on the message (intents.distress) BEFORE anything is written  [choice A]
     -> stop any running exercise, hand the turn back to the companion. TSD still runs in the background as locked.
  3. latest known TSD tier HIGH/CRITICAL -> crisis (policy R1), exercise stopped
  4. inside an exercise: step-aware intent reading with abstention -> one transition of a plain state machine
     (journeys.json); outside: policy.decide() says whether to offer, the user may also ask to start
  5. reply = short LLM acknowledgement (checked sentence by sentence) + fixed reviewed line(s)  [choice B]
  6. UI actions (start/pause/stop breathing, save task, save go-to) come only from here, never from the LLM
  7. a new signed state token is the last event

turn_events() is a generator, so the backend can stream events in order:
  urgent ui (stop/pause) -> companion_state -> sentence... -> ui -> handoff -> state
A "handoff" event means: the director has nothing to say this turn; the backend runs the normal companion reply
(to="companion"), the crisis flow (to="crisis", UX Flow 4), or the CBT module (to="cbt_module", not built yet).

Inputs per turn (all optional except now):
  text, client_event ("none" | "playback_done" | "playback_stopped" | "start_breathing" | "start_grounding" |
  "start_plan"), tier (latest known TSD risk_category, or None if the check is unavailable), score, flags,
  policy_event / crisis_path (pass-through for UX Flow 4), lang (onboarding preference), now (epoch seconds).
"""
import json
from pathlib import Path

import compose as K
import intents as I
import policy as P
import state_token as T

HERE = Path(__file__).resolve().parent
DATA = json.loads((HERE / "journeys.json").read_text(encoding="utf-8"))
J, COMMON = DATA["journeys"], DATA["common"]
MAX_REPAIRS = 2                 # engineering default: after 2 clarifications, offer to leave it (no 3rd repeat)
LAPSE_WORDS = 5                 # an unmatched reply this long at an offer = the user kept chatting; offer lapses
CLIENT_EVENTS = ("none", "playback_done", "playback_stopped", "start_breathing", "start_grounding", "start_plan")
START_JOURNEY = {"start_breathing": ("breathing", "start_grounding"), "start_grounding": ("grounding", "start_grounding"),
                 "start_plan": ("plan", "start_plan")}
_READER = I.IntentReader()


def fresh_state():
    return {"rev": 0, "policy": P.initial_state(), "ex": None, "go_to": None, "lang": None}


def new_token(secret=None):
    return T.sign(fresh_state(), secret)


class _Turn:
    def __init__(self, turn, st, phrase_fn, reader):
        self.t, self.st, self.phrase_fn, self.reader = turn, st, phrase_fn, reader
        self.tier = P.parse_tier(turn["tier"]) if turn.get("tier") is not None else None
        self.now = float(turn["now"])
        self.decided = False
        self.urgent, self.lines, self.ui, self.handoff, self.why = [], [], [], None, []
        self.ack_goal = None
        self.cs_default = ("neutral", 0.4)

    # ---- policy -------------------------------------------------------------------------------------------
    def decide(self, event="none"):
        if self.tier is None:
            raise RuntimeError("risk check unavailable")
        d = P.decide({"tier": self.tier, "score": None if self.decided else self.t.get("score"),
                      "flags": self.t.get("flags") or [], "event": event, "now": self.now,
                      "crisis_path": self.t.get("crisis_path")}, self.st["policy"])
        self.decided = True
        self.st["policy"] = d.state
        self.why.append(f"policy {event} -> {d.action}: {'; '.join(d.reasons)}")
        return d

    def finish_bookkeeping(self):
        if not self.decided and self.t.get("score") is not None:
            self.st["policy"] = P.record_score(self.st["policy"], self.t["score"])

    # ---- lines --------------------------------------------------------------------------------------------
    def say(self, entry, **fmt):
        lang = self.st["lang"]
        text = entry[lang] if isinstance(entry, dict) else entry
        if fmt:
            text = text.format(**{k: str(v)[:80] for k, v in fmt.items()})
        self.lines.extend(K.split_fixed(text))

    def end_exercise(self, keep_talking=True, reason=""):
        ex = self.st["ex"]
        if ex and ex.get("playing"):
            self.urgent.append({"type": "ui_action", "name": "stop_breathing", "args": {}})
        self.st["ex"] = None
        if self.st["policy"]["mode"] in ("grounding", "plan", "cbt"):
            self.st["policy"] = {**self.st["policy"], "mode": "chat"}   # leaving an exercise is always allowed
        if keep_talking:
            self.say(COMMON["keep_talking"])
        self.why.append(f"exercise ended ({reason})")


def _step(ex):
    return J[ex["j"]]["steps"][ex["step"]]


def _enter(tt, target, prefix=None):
    """Move to `target`, chaining say-only steps, collecting lines/ui until a step that waits for the user."""
    ex = tt.st["ex"]
    if prefix:
        tt.say(prefix)
    for _ in range(20):
        if target in ("@end", "@end_quiet"):
            tt.end_exercise(keep_talking=target == "@end", reason="journey complete")
            return
        if target == "@handoff_cbt":
            tt.end_exercise(keep_talking=False, reason="CBT module takes over")
            tt.st["policy"] = {**tt.st["policy"], "mode": "cbt"}
            tt.handoff = {"to": "cbt_module", "reason": "thought-reflection steps not built yet (Day 2)"}
            return
        if target.startswith("@journey:"):
            _, j, s = target.split(":")
            ex["j"], target = j, s
            continue
        ex["step"] = target
        step = J[ex["j"]]["steps"][target]
        if step.get("say"):
            data = ex.get("data", {})
            tt.say(step["say"], **{k: data.get(k, "") for k in ("activity", "when")}) if "{" in step["say"]["en"] \
                else tt.say(step["say"])
        elif step.get("clarify"):
            tt.say(COMMON[step["clarify"]])
        if step.get("ack") and tt.ack_goal is None and (tt.t.get("text") or "").strip():
            tt.ack_goal = step["ack"]
        if step.get("ui"):
            ui = step["ui"]
            args = dict(ui.get("args", {}))
            if ui["name"] == "start_breathing":
                args["cue_audio"] = args["cue_audio"][tt.st["lang"]]
                args["minutes_note"] = "about one minute; 'at your own pace' (user need not match the avatar)"
            if ui["name"] == "save_task":
                args = {k: ex["data"].get(k) for k in ("activity", "when", "commitment")}
            if ui["name"] == "save_go_to":
                tt.st["go_to"] = ex["j"]
                args = {"journey": ex["j"], "exercise_id": J[ex["j"]]["exercise_id"]}
            tt.ui.append({"type": "ui_action", "name": ui["name"], "args": args})
        if step.get("wait") == "playback":
            ex["playing"] = True
            return
        if "then" in step:
            target = step["then"]
            continue
        return
    raise RuntimeError("journey loop")


def _begin(tt, journey, step, prefix=None):
    tt.st["ex"] = {"j": journey, "step": step, "lang": tt.st["lang"], "data": {}, "repairs": 0, "playing": False}
    _enter(tt, step, prefix)


def _continue(tt):
    ex, text, ev = tt.st["ex"], (tt.t.get("text") or "").strip(), tt.t.get("client_event") or "none"
    step = _step(ex)

    if ex.get("playing"):
        if ev == "playback_done":
            ex["playing"] = False
            tt.cs_default = ("joy", 0.4)
            return _enter(tt, step["on"]["playback_done"])
        if ev == "playback_stopped":
            ex["playing"] = False
            return _enter(tt, "stopped")
        if text:
            intent, how = tt.reader.read(text, ["stop"])
            if intent == "stop":
                tt.urgent.append({"type": "ui_action", "name": "stop_breathing", "args": {}})
                ex["playing"] = False
                return _enter(tt, "stopped")
            tt.urgent.append({"type": "ui_action", "name": "pause_breathing", "args": {}})
            ex["playing"] = False
            return _enter(tt, "paused")
        return None
    if not text:
        return None

    expected = step.get("expect", [])
    if "number" in expected:
        n = I.number_0_10(text)
        intent, how = tt.reader.read(text, [e for e in expected if e != "number"])
        if intent != "stop" and n is not None:
            intent, how = "number", f"number {n}"
            ex["data"][step["store"]] = n
        elif intent != "stop":
            intent = None
    else:
        intent, how = tt.reader.read(text, expected)
    tt.why.append(f"step {ex['j']}.{ex['step']}: read {intent!r} ({how})")

    if intent is None or step["on"].get(intent) == "@repair":
        n_words = len(I.normalise(text).split())
        if step.get("policy") and n_words >= LAPSE_WORDS and intent is None:
            tt.why.append("offer lapsed: the user kept chatting")
            tt.st["ex"] = None
            d = tt.decide("none") if tt.tier else None
            if d and d.action == "OFFER_CBT":                        # policy may still offer CBT on this turn
                return _begin(tt, "cbt", "offer")
            tt.handoff = {"to": "companion", "reason": "user kept chatting; offer lapsed"}
            return None
        ex["repairs"] += 1
        if ex["repairs"] > MAX_REPAIRS:
            if step.get("policy") and tt.st["policy"]["pending_offer"] and tt.tier:
                tt.decide("decline_offer")
            tt.say(COMMON["repair_exhausted"])
            return tt.end_exercise(reason="repair budget used")
        return tt.say(COMMON[step["clarify"]])
    ex["repairs"] = 0
    if step.get("store") and intent == "answer":
        ex["data"][step["store"]] = text
    target = step["on"][intent]

    # policy hooks at offer/explain steps
    if step.get("policy") and intent in step["policy"]:
        event = step["policy"][intent]
        if tt.st["policy"]["pending_offer"] is None:              # e.g. an alternative offered after a "no"
            if event == "decline_offer":
                target = "@end"                                   # a "no" to the alternative ends it, no loop
            event = {"accept_offer": "start_plan" if ex["j"] == "plan" else "start_grounding"}.get(event)
        if event:
            if tt.tier is None and event in ("accept_offer", "start_grounding", "start_plan"):
                tt.st["ex"] = None
                tt.handoff = {"to": "companion", "reason": "risk check unavailable: no exercise is started"}
                return None
            d = tt.decide(event) if tt.tier else None
            if d and d.action == "OFFER_GROUNDING":                # R7: CBT declined -> one calm alternative
                j = tt.st["go_to"] or "breathing"
                return _begin(tt, j, "offer", prefix=COMMON["ok_no_pressure"])
    if target == "@r7":
        return tt.end_exercise(reason="CBT declined; policy offered nothing")
    if target.startswith("@journey:") and target.endswith(":start"):
        if tt.tier is None:
            tt.st["ex"] = None
            tt.handoff = {"to": "companion", "reason": "risk check unavailable: no exercise is started"}
            return None
        tt.decide("start_grounding")

    if step.get("branch") == "mood":
        m = I.mood(text)
        ex["data"]["mood"] = m
        if m == "worse":
            target = "worse_end"
        elif tt.st["go_to"] == ex["j"]:
            target = "plain_end"
    if step.get("branch") == "commitment" and intent == "number":
        target = "t3b" if ex["data"]["commitment"] < 7 else "t4"     # Brief Action Planning: < 7 -> smaller
    if target in ("start",) and J[ex["j"]]["mode"] != "cbt":
        tt.cs_default = ("joy", 0.3)
    return _enter(tt, target)


def turn_events(turn, token, *, secret=None, phrase_fn=None, reader=None):
    """Generator of events for one user turn. See module docstring."""
    try:
        st = T.verify(token, secret) if token else fresh_state()
        reset = None
    except T.TokenError as e:
        st, reset = fresh_state(), str(e)
    st = {**fresh_state(), **st}
    ev = turn.get("client_event") or "none"
    if ev not in CLIENT_EVENTS:
        raise ValueError(f"unknown client_event {ev!r}")
    tt = _Turn(turn, st, phrase_fn, reader or _READER)
    if reset:
        tt.why.append(f"state token rejected ({reset}); started fresh")
    text = (turn.get("text") or "").strip()
    st["lang"] = I.detect_lang(text) or (st["ex"] or {}).get("lang") or st.get("lang") or turn.get("lang") or "en"
    if st["ex"]:
        st["ex"]["lang"] = st["lang"]

    def finish():
        tt.finish_bookkeeping()
        for e in tt.urgent:
            yield e
        if tt.lines:
            sents, src = [], None
            if tt.ack_goal:
                ex = st["ex"] or {}
                title = J.get(ex.get("j", ""), {}).get("exercise_id", "an exercise")
                d = K.direction(tt.ack_goal, st["lang"], text, " ".join(tt.lines), title)
                cs, sents, src, notes = K.acknowledge(tt.phrase_fn, d, COMMON["ack_fallback"][st["lang"]],
                                                      seed=st["rev"], default_state=tt.cs_default)
                tt.why += [f"ack {src}: {n}" for n in notes] or [f"ack {src}"]
            else:
                cs = {"emotion": tt.cs_default[0], "intensity": tt.cs_default[1]}
            yield {"type": "companion_state", **cs}
            for s in sents:
                yield {"type": "sentence", "text": s, "source": src}
            for s in tt.lines:
                yield {"type": "sentence", "text": s, "source": "reviewed"}
        for e in tt.ui:
            yield e
        if tt.handoff:
            yield {"type": "handoff", **tt.handoff}
        st["rev"] += 1
        yield {"type": "state", "token": T.sign(st, secret), "rev": st["rev"], "trace": tt.why}

    # 1. distress pre-check (choice A): before anything is generated
    hit = I.distress(text) if text else None
    if hit:
        tt.why.append(f"distress language ({hit!r}): exercise stopped before generation")
        if st["ex"]:
            tt.end_exercise(keep_talking=False, reason="distress language")
        if tt.tier in P.CRISIS_TIERS:
            tt.decide("none")
            tt.handoff = {"to": "crisis", "reason": f"tier {tt.tier}"}
        else:
            tt.handoff = {"to": "companion", "reason": "distress language; no exercise text",
                          "prioritise_risk_check": True}
        yield from finish()
        return

    # 2. crisis tiers (latest known TSD result) and the crisis conversation itself (UX Flow 4 owns it)
    if tt.tier in P.CRISIS_TIERS or st["policy"]["mode"] == "crisis":
        if st["ex"]:
            tt.end_exercise(keep_talking=False, reason=f"crisis (tier {tt.tier})")
        if tt.tier is not None:
            tt.decide(turn.get("policy_event") or "none")
        tt.handoff = {"to": "crisis" if st["policy"]["mode"] == "crisis" else "companion",
                      "reason": f"tier {tt.tier}; mode {st['policy']['mode']}"}
        yield from finish()
        return

    # 3. inside an exercise
    if st["ex"]:
        _continue(tt)
        if not tt.lines and not tt.ui and not tt.urgent and not tt.handoff and st["ex"] is None:
            tt.handoff = {"to": "companion", "reason": "exercise ended"}
        yield from finish()
        return

    # 4. plain chat: did the user ask to start one? (button = client_event, or words)
    start = ev if ev in START_JOURNEY else (I.read_start(text) if text else None)
    if start:
        journey, event = START_JOURNEY[start]
        if tt.tier is None:
            tt.handoff = {"to": "companion", "reason": "risk check unavailable: no exercise is started"}
        else:
            d = tt.decide(event)
            if d.action in ("ENTER_GROUNDING", "ENTER_PLAN"):
                tt.cs_default = ("joy", 0.3)
                _begin(tt, journey, "start")
            else:
                tt.handoff = {"to": "companion", "reason": f"policy said {d.action}"}
        yield from finish()
        return

    # 5. plain chat: should the system offer something?
    if st["policy"]["mode"] in ("grounding", "plan"):            # stale mode with no exercise running
        st["policy"] = {**st["policy"], "mode": "chat"}
        tt.why.append("stale exercise mode reset to chat")
    if tt.tier is None:
        tt.handoff = {"to": "companion", "reason": "risk check unavailable: no offers"}
    elif st["policy"]["mode"] != "chat":
        tt.decide("none")
        tt.handoff = {"to": "cbt_module" if st["policy"]["mode"] == "cbt" else "companion",
                      "reason": f"mode {st['policy']['mode']}"}
    else:
        d = tt.decide("none")
        if d.action == "OFFER_GROUNDING":
            _begin(tt, st["go_to"] or "breathing", "offer")
        elif d.action == "OFFER_CBT":
            _begin(tt, "cbt", "offer")
        else:
            tt.handoff = {"to": "companion", "reason": d.action}
    yield from finish()


def handle_turn(turn, token, **kw):
    return list(turn_events(turn, token, **kw))


def on_risk(token, tier, now, *, secret=None):
    """The background TSD result arrived (Gate 1b-concurrency (c): an independent event, the in-flight reply is not
    rewritten). HIGH/CRITICAL -> stop any exercise, go to crisis. Returns events like turn_events."""
    if P.parse_tier(tier) not in P.CRISIS_TIERS:
        st = T.verify(token, secret)
        return [{"type": "state", "token": token, "rev": st["rev"], "trace": [f"risk {tier}: nothing to do"]}]
    return handle_turn({"text": None, "tier": tier, "now": now}, token, secret=secret)
