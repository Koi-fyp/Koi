"""Tests for the exercise director (director.py, intents.py, compose.py, state_token.py).   python test_director.py
All offline: the LLM is a stub. These test the hidden logic, not how natural the real model sounds."""
import copy
import sys

import compose as K
import director as D
import intents as I
import policy as P
import state_token as T

SECRET = "test-secret"
fails = []


def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        fails.append(name)


ACKS = {"en": "That sounds really heavy. Thank you for telling me.",
        "ur-roman": "Samajh sakta hoon, yeh kaafi heavy lag raha hai.",
        "ur": "میں سمجھ سکتا ہوں، یہ کافی بھاری لگ رہا ہے۔"}


def good(d):
    return {"emotion": "sorrow", "intensity": 0.5}, iter(w + " " for w in ACKS[d["lang"]].split())


class Convo:
    def __init__(self, phrase_fn=None, token=None):
        self.tok, self.now, self.pf, self.log = token or D.new_token(SECRET), 1_000_000.0, phrase_fn, []

    def fork(self):
        c = Convo(self.pf, self.tok)
        c.now = self.now
        return c

    def say(self, text=None, ev="none", tier="LOW", score=None):
        self.now += 20
        turn = {"text": text, "client_event": ev, "tier": tier, "score": score, "now": self.now}
        evs = D.handle_turn(turn, self.tok, secret=SECRET, phrase_fn=self.pf)
        self.tok = evs[-1]["token"]
        self.log.append(evs)
        return evs

    @property
    def st(self):
        return T.verify(self.tok, SECRET)


def sents(evs, source=None):
    return [e["text"] for e in evs if e["type"] == "sentence" and (source is None or e["source"] == source)]


def ui(evs):
    return [e["name"] for e in evs if e["type"] == "ui_action"]


def handoff(evs):
    h = [e for e in evs if e["type"] == "handoff"]
    return h[0] if h else None


def has(evs, fragment):
    return any(fragment in s for s in sents(evs))


# ---------------------------------------------------------------------------------------------- token
t = T.sign({"rev": 3, "x": 1}, SECRET)
check("token: round trip", T.verify(t, SECRET)["x"] == 1)
bad = t[:-1] + ("0" if t[-1] != "0" else "1")
try:
    T.verify(bad, SECRET); ok = False
except T.TokenError:
    ok = True
check("token: edited token is rejected", ok)
body = t.split(".")[0]
try:
    T.verify(body[:-2] + "AA." + t.split(".")[1], SECRET); ok = False
except T.TokenError:
    ok = True
check("token: edited payload is rejected", ok)
evs = D.handle_turn({"text": "hi", "tier": "LOW", "now": 1}, bad, secret=SECRET)
check("director: tampered token -> fresh state, says why", "rejected" in evs[-1]["trace"][0])
try:
    T.sign({}, None) if not __import__("os").environ.get("KOI_DIRECTOR_SECRET") else (_ for _ in ()).throw(T.TokenError("x"))
    ok = False
except T.TokenError:
    ok = True
check("token: no secret -> refuses to sign", ok)

# ---------------------------------------------------------------------------------------------- intents
R = I.IntentReader()
OFFER = ["accept", "decline", "what_is_it", "stop"]
ANSWER = ["answer", "next", "stop"]
HELD_OUT = [  # written separately from the lexicon/examples; spellings and phrasings not listed there
    ("yes let's", OFFER, "accept"), ("ok sure", OFFER, "accept"), ("Sure thing", OFFER, "accept"),
    ("hanji kar lete", OFFER, "accept"), ("ji zaroor", OFFER, "accept"), ("chalo theek hai", OFFER, "accept"),
    ("جی ٹھیک ہے", OFFER, "accept"), ("ہاں کر لیتے ہیں", OFFER, "accept"), ("thik h", OFFER, "accept"),
    ("nope", OFFER, "decline"), ("nahi yaar abhi nahi", OFFER, "decline"), ("no thank you", OFFER, "decline"),
    ("nahin", OFFER, "decline"), ("ابھی نہیں", OFFER, "decline"), ("theek hai lekin baad mein", OFFER, "decline"),
    ("I'd rather not", OFFER, "decline"), ("nhi krna", OFFER, "decline"),
    ("what's that?", OFFER, "what_is_it"), ("ye kya hota hai", OFFER, "what_is_it"), ("kaise karte hain", OFFER, "what_is_it"),
    ("یہ کیا ہے؟", OFFER, "what_is_it"), ("pata nahi", OFFER, "what_is_it"), ("not sure", OFFER, "what_is_it"),
    ("theek hai, abhi nahi", OFFER, None), ("nahi, karna hai", OFFER, None), ("hmm", OFFER, None),
    ("stop", ANSWER, "stop"), ("bas karo", ANSWER, "stop"), ("بس", ANSWER, "stop"),
    ("ho gaya", ANSWER, "next"), ("done", ANSWER, "next"), ("کر لیا", ANSWER, "next"),
    ("bas thora tired hoon", ANSWER, "answer"), ("my desk and a fan", ANSWER, "answer"),
    ("meri table aur pankha", ANSWER, "answer"), ("nothing much", ANSWER, "answer"),
    ("not my thing", ["not_for_me", "not_now", "decline", "stop", "answer"], "not_for_me"),
    ("mujhe pasand nahi ye sab", ["not_for_me", "not_now", "decline", "stop", "answer"], "not_for_me"),
    ("abhi time nahi", ["not_for_me", "not_now", "decline", "stop", "answer"], "not_now"),
]
right = [(t, exp, R.read(t, e)[0]) for t, e, exp in HELD_OUT]
wrong = [(t, exp, got) for t, exp, got in right if got != exp]
for t, exp, got in wrong:
    print(f"     intent miss: {t!r}: expected {exp!r}, got {got!r}")
check(f"intents: held-out set {len(HELD_OUT) - len(wrong)}/{len(HELD_OUT)} (None = should ask again)", not wrong)
check("intents: 'chalo na' (please, let's) is not a 'no'", R.read("chalo na", OFFER)[0] == "accept")
check("intents: 'bas' inside a sentence is not 'stop'", R.read("bas thora tired hoon", ANSWER)[0] == "answer")
check("intents: Roman 'teen' is 3, not English 'ten'", I.number_0_10("teen") == 3 and I.number_0_10("ten") == 10)
check("intents: numbers in Urdu digits and words", I.number_0_10("۶") == 6 and I.number_0_10("سات") == 7)
check("intents: 'I hate breathing' does not start breathing", I.read_start("I hate breathing") is None)
check("intents: a short 'ok' never switches language", I.detect_lang("ok") is None)
check("distress: 'done with everything' is distress, 'done' is not",
      I.distress("I'm done with everything") and not I.distress("done"))
check("distress: Urdu script and Roman Urdu", I.distress("میں مرنا چاہتا ہوں") and I.distress("ab bardasht nahi hota"))

# ---------------------------------------------------------------------------------------------- compose
d = K.direction("ack", "en", "hi", "Next line.", "x")
cs, s, src, _ = K.acknowledge(good, d, ["Okay."], 0)
check("compose: a good acknowledgement is used", src == "generated" and s[0].startswith("That sounds"))
BAD = {"asks a question": "How are you feeling?", "a number": "Try 4 seconds in.",
       "claims to see the user": "You look calmer already.", "breathing instruction": "Take a deep breath first.",
       "diagnosis": "This sounds like an anxiety disorder.", "too long": " ".join(["word"] * 40) + "."}
for name, txt in BAD.items():
    calls = []
    pf = (lambda t: (lambda dd: (calls.append(1), ({"emotion": "joy"}, iter([t])))[1]))(txt)
    cs, s, src, notes = K.acknowledge(pf, d, ["Okay."], 0)
    check(f"compose: LLM acknowledgement that {name} -> retried once, then reviewed fallback",
          src == "fallback" and s == ["Okay."] and len(calls) == 2)
cs, s, src, _ = K.acknowledge(lambda dd: ({}, iter(["Okay, got it. ", "Do it 5 times?"])), d, ["F."], 0)
check("compose: sentence gate releases the good sentence and cuts the bad one", s == ["Okay, got it."])
d_ur = K.direction("ack", "ur", "hi", "x", "x")
cs, s, src, _ = K.acknowledge(lambda dd: ({}, iter(["I understand."])), d_ur, ["ٹھیک ہے۔"], 0)
check("compose: English acknowledgement in an Urdu conversation -> fallback", src == "fallback")
cs, s, src, _ = K.acknowledge(lambda dd: (_ for _ in ()).throw(TimeoutError("model down")), d, ["Okay."], 0)
check("compose: model error/timeout -> reviewed fallback, no crash", src == "fallback")
check("compose: avatar emotion limited to canon's 5 and calm ones in exercises",
      K.safe_companion_state({"emotion": "angry", "intensity": 3})["emotion"] == "neutral"
      and K.safe_companion_state({"emotion": "angry", "intensity": 3})["intensity"] == 1.0
      and K.safe_companion_state({"emotion": "rage"})["emotion"] == "neutral")
check("compose: stage direction tells the model not to ask, count or observe",
      all(x in K.direction_prompt(d) for x in ("Do not ask a question", "numbers", "see or hear")))

# ---------------------------------------------------------------------------------------------- journeys
c = Convo(good)
e = c.say("today was really heavy, I just feel tired of everything", tier="MODERATE", score=0.5)
check("breathing: MODERATE -> companion acknowledges, then the reviewed offer",
      sents(e, "generated") and has(e, "slow your breathing down with me"))
check("breathing: companion_state comes first, state token last", e[0]["type"] == "companion_state" and e[-1]["type"] == "state")
e = c.say("what's that?")
check("breathing: 'what's that?' -> explanation, offer stays open (R8)",
      has(e, "at your own pace") and c.st["policy"]["pending_offer"] == "grounding")
e = c.say("ok let's try")
check("breathing: accept -> start line, then start_breathing UI action (after the words)",
      has(e, "if you feel dizzy") and ui(e) == ["start_breathing"] and e.index([x for x in e if x["type"] == "ui_action"][0]) >
      max(i for i, x in enumerate(e) if x["type"] == "sentence"))
args = [x for x in e if x["type"] == "ui_action"][0]["args"]
check("breathing: sourced pacing 4 s in / 6 s out, cues in the user's language", args["inhale_s"] == 4 and
      args["exhale_s"] == 6 and args["cue_audio"] == ["Breathe in", "Breathe out"])
check("breathing: policy mode is grounding while it runs", c.st["policy"]["mode"] == "grounding" and c.st["ex"]["playing"])
playing = c.fork()
e = c.say(ev="playback_done")
check("breathing: playback done -> 'How are you feeling now?'", has(e, "How are you feeling now"))
e = c.say("a bit better actually")
check("breathing: better -> go-to question (UX Flow 5 'save as my go-to')", has(e, "your go-to"))
e = c.say("yes")
check("breathing: yes -> saved, exercise over, back to chat", "save_go_to" in ui(e) and c.st["ex"] is None
      and c.st["go_to"] == "breathing" and c.st["policy"]["mode"] == "chat" and has(e, "keep talking"))

p = playing.fork()
e = p.say("stop")
check("breathing: 'stop' while playing -> stop_breathing is the FIRST event", e[0] == {"type": "ui_action", "name": "stop_breathing", "args": {}}
      and has(e, "let's stop here") and p.st["ex"] is None)
p = playing.fork()
e = p.say("wait my mom is calling")
check("breathing: other words while playing -> pause first, then 'carry on or stop?'", e[0]["name"] == "pause_breathing"
      and has(e, "carry on"))
e = p.say("haan")
check("breathing: 'haan' -> resume", ui(e) == ["resume_breathing"] and p.st["ex"]["playing"])
p = playing.fork()
e = p.say(ev="playback_stopped")
check("breathing: stop button -> stopped politely", has(e, "let's stop here") and p.st["ex"] is None)

c = Convo(good)
c.say("work is just a lot right now", tier="MODERATE", score=0.5)
e = c.say("no")
check("decline: 'no' -> Socratic 'why not' (UX Flow 5), not a dead end", has(e, "isn't your thing"))
f = c.fork()
e = f.say("not my thing really")
check("decline: 'not my thing' -> alternative technique + 'just keep talking'", has(e, "grounding exercise") and has(e, "keep talking"))
g = f.fork()
e = g.say("ok")
check("decline: accept the alternative -> grounding starts", has(e, "notice what you're feeling") and g.st["policy"]["mode"] == "grounding")
e = f.say("no")
check("decline: 'no' to the alternative ends it (no ping-pong)", f.st["ex"] is None and has(e, "keep talking"))
e = c.say("abhi nahi")
check("decline: 'abhi nahi' -> 'another time' in Roman Urdu (the user switched), ends",
      has(e, "kisi aur waqt") and c.st["ex"] is None and c.st["lang"] == "ur-roman")

c = Convo(good)
c.say("everything is a lot", tier="MODERATE", score=0.5)
e1 = c.say("theek hai, abhi nahi"); e2 = c.say("hmm"); e3 = c.say("hmm")
check("repair: unclear reply -> asks again (twice, in the user's Roman Urdu), never guesses",
      has(e1, "Bas confirm") and has(e2, "Bas confirm"))
check("repair: third unclear reply -> leaves it, offer counted as declined",
      has(e3, "Koi pressure nahi") and c.st["ex"] is None and c.st["policy"]["pending_offer"] is None)

c = Convo(good)
c.say("everything is a lot", tier="MODERATE", score=0.5)
e = c.say("actually I wanted to tell you about my cousin's wedding yesterday")
check("lapse: user keeps chatting at an offer -> offer dropped, companion replies normally",
      handoff(e)["to"] == "companion" and c.st["ex"] is None and not sents(e))

c = Convo(good)
c.say("can we do a grounding exercise")
for a in ["anxious I think", "done", "my laptop, a cup, the window", "fan and some traffic", "the chair"]:
    e = c.say(a)
check("grounding: one question per turn, all five steps, then post-check", has(e, "back to where you are") and has(e, "How are you feeling now"))
e = c.say("honestly still bad")
check("grounding: feeling worse -> no go-to question, offer to talk", has(e, "talk about what's going on")
      and not has(e, "go-to") and c.st["ex"] is None and not has(e, "keep talking"))

c = Convo(good)
e = c.say("let's make a plan")
check("plan: user asks -> one small thing (UX Flow 12)", has(e, "one small thing") and c.st["policy"]["mode"] == "plan")
c.say("go for a walk"); c.say("after asr")
e = c.say("5")
check("plan: confidence 5 (< 7) -> make it smaller (Brief Action Planning)", has(e, "a bit smaller"))
c.say("walk to the corner shop")
e = c.say("saat")
saved = [x for x in e if x["type"] == "ui_action" and x["name"] == "save_task"]
check("plan: 'saat' = 7 -> plan saved with the smaller activity", saved and saved[0]["args"] == {
    "activity": "walk to the corner shop", "when": "after asr", "commitment": 7} and has(e, "walk to the corner shop"))
c = Convo(good)
c.say("let's make a plan"); c.say("call Ali"); c.say("tonight")
e = c.say("I'm not sure")
check("plan: a non-number to the 0-10 question -> asks for just a number", has(e, "number from 0 to 10"))

c = Convo(good)
for i in range(3):
    e = c.say("I keep thinking nobody wants me around", tier="MODERATE", score=0.6)
    if has(e, "look at that thought"):
        break
check("CBT: sustained scores -> CBT offer (policy R5)", has(e, "look at that thought"))
f = c.fork()
e = f.say("no thanks")
check("CBT: 'no' -> one calm alternative (R7)", has(e, "That's okay.") and has(e, "slow your breathing"))
e = c.say("ok")
check("CBT: 'ok' -> handed to the CBT module (thought steps are Day 2)", handoff(e)["to"] == "cbt_module")

# ---------------------------------------------------------------------------------------------- languages
c = Convo(good)
e = c.say("آج دل بہت بھاری ہے", tier="MODERATE", score=0.5)
check("language: Urdu script -> Urdu acknowledgement and Urdu offer", has(e, "سانس آہستہ") and has(e, "بھاری لگ رہا"))
e = c.say("ok")
check("language: a bare 'ok' keeps Urdu", has(e, "سانس اندر"))
c = Convo(good)
e = c.say("yaar aaj bohat heavy feel ho raha hai", tier="MODERATE", score=0.5)
check("language: Roman Urdu -> Roman Urdu lines", has(e, "saans thori aahista"))
c = Convo(None)
e = c.say("today was heavy", tier="MODERATE", score=0.5)
check("no LLM at all (scripted mode) -> reviewed fallback acknowledgement + offer still works",
      sents(e, "fallback") and has(e, "slow your breathing"))

# ---------------------------------------------------------------------------------------------- safety
SCRIPTS = {   # (journey) -> list of user turns that walk through every waiting step
    "breathing": [("everything is a lot", "none", "MODERATE", 0.5), ("what is it", "none", "LOW", None),
                  ("yes", "none", "LOW", None), (None, "playback_done", "LOW", None), ("better", "none", "LOW", None)],
    "breathing_pause": [("everything is a lot", "none", "MODERATE", 0.5), ("yes", "none", "LOW", None),
                        ("hold on", "none", "LOW", None)],
    "decline": [("everything is a lot", "none", "MODERATE", 0.5), ("no", "none", "LOW", None),
                ("not for me", "none", "LOW", None)],
    "grounding": [("grounding please", "none", "LOW", None), ("sad", "none", "LOW", None), ("done", "none", "LOW", None),
                  ("a lamp", "none", "LOW", None), ("birds", "none", "LOW", None)],
    "plan": [("let's make a plan", "none", "LOW", None), ("walk", "none", "LOW", None), ("evening", "none", "LOW", None),
             ("3", "none", "LOW", None)],
}
DISTRESS_LINES = ["I can't take this anymore", "ab bardasht nahi hota", "میں مرنا چاہتا ہوں"]
points = []
for name, script in SCRIPTS.items():
    c = Convo(good)
    for text, ev, tier, score in script:
        c.say(text, ev, tier, score)
        if c.st["ex"]:
            points.append((f"{name}@{c.st['ex']['j']}.{c.st['ex']['step']}", c.fork()))
n_ok_d = n_ok_h = 0
for label, base in points:
    was_playing = base.st["ex"]["playing"]
    for line in DISTRESS_LINES:
        x = base.fork()
        e = x.say(line)
        good_d = (not sents(e) and handoff(e)["to"] == "companion" and handoff(e).get("prioritise_risk_check")
                  and x.st["ex"] is None and (not was_playing or e[0]["name"] == "stop_breathing"))
        n_ok_d += bool(good_d)
        if not good_d:
            print("     distress miss at", label, line, e)
    x = base.fork()
    e = x.say("hmm", tier="HIGH", score=0.8)
    good_h = (not sents(e) and handoff(e)["to"] == "crisis" and x.st["policy"]["mode"] == "crisis"
              and x.st["ex"] is None and (not was_playing or e[0]["name"] == "stop_breathing"))
    n_ok_h += bool(good_h)
check(f"distress at every waiting step ({len(points)} steps x 3 languages): exercise stopped before any "
      f"exercise text, companion takes over, risk check prioritised", n_ok_d == len(points) * 3)
check(f"HIGH tier at every waiting step ({len(points)} steps): no exercise text, crisis, breathing stopped first",
      n_ok_h == len(points))
check("safety sweep is not vacuous (covers playing, offer, grounding, plan steps)",
      any("playing" in l for l, _ in points) and any(".offer" in l for l, _ in points)
      and any("plan." in l for l, _ in points) and any(".g4" in l for l, _ in points))

c = Convo(good)
c.say("everything is a lot", tier="MODERATE", score=0.5); c.say("yes")
e = D.on_risk(c.tok, "CRITICAL", c.now + 5, secret=SECRET)
check("background TSD result CRITICAL mid-breathing -> stop_breathing first, then crisis handoff",
      e[0]["name"] == "stop_breathing" and handoff(e)["to"] == "crisis")
e = D.on_risk(c.tok, "LOW", c.now + 5, secret=SECRET)
check("background TSD result LOW -> nothing happens (token unchanged)", len(e) == 1 and e[0]["token"] == c.tok)

c = Convo(good)
e = c.say("can we do a breathing exercise", tier=None)
check("risk check unavailable -> no exercise is started", not ui(e) and handoff(e)["to"] == "companion")
c = Convo(good)
c.say("everything is a lot", tier="MODERATE", score=0.5)
e = c.say("yes", tier=None)
check("risk check unavailable at 'yes' -> still no exercise started", not ui(e) and c.st["ex"] is None)
c = Convo(good)
e = c.say("I feel fine today", tier=None)
check("risk check unavailable -> no offers", handoff(e)["to"] == "companion" and not sents(e))

all_gen = [s for conv_logs in [c.log] for evs in conv_logs for s in sents(evs, "generated")]
check("every generated sentence that reached the user passes the sentence check",
      all(K.check_sentence(s, I.detect_lang(s) or "en") is None for s in all_gen))

turn = {"text": "everything is a lot", "tier": "MODERATE", "score": 0.5, "now": 5.0}
snap = copy.deepcopy(turn)
tok0 = D.new_token(SECRET)
a = D.handle_turn(turn, tok0, secret=SECRET, phrase_fn=good)
b = D.handle_turn(turn, tok0, secret=SECRET, phrase_fn=good)
check("deterministic for the same input; input turn not mutated", a == b and turn == snap)
try:
    D.handle_turn({"text": "x", "tier": "HIGH_CRISIS", "now": 1}, tok0, secret=SECRET); ok = False
except ValueError:
    ok = True
check("unknown tier string raises (enum G15 still open)", ok)

print("\nALL PASSED" if not fails else "\nFAILED: " + ", ".join(fails))
sys.exit(1 if fails else 0)
