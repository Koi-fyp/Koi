"""Tests for policy.py (G2 CBT-offer trigger, G3 mode routing).   Run: python test_policy.py"""
import copy
import itertools
import sys

import policy as P

fails = []
H, DAY = 3600, 24 * 3600


def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        fails.append(name)


def raises(fn):
    try:
        fn()
    except ValueError:
        return True
    return False


def turn(tier="LOW", score=None, flags=(), event="none", now=0.0, path=None):
    t = {"tier": tier, "score": score, "flags": list(flags), "event": event, "now": now}
    if path:
        t["crisis_path"] = path
    return t


def run(seq, state=None):
    st, out = state or P.initial_state(), []
    for t in seq:
        d = P.decide(t, st)
        st = d.state
        out.append(d)
    return out


def warm(now=0):   # three turns of MODERATE-level scores -> CBT offer on the third
    return [turn("LOW", 0.6, now=now), turn("LOW", 0.6, now=now + 1), turn("MODERATE", 0.6, now=now + 2)]


# ---- R1 crisis preemption (every mode/event, except the explicit crisis exit itself)
ok = True
for mode, tier, ev in itertools.product(P.MODES, P.CRISIS_TIERS, P.EVENTS):
    if mode == "crisis" and ev == "crisis_resolved":
        continue
    d = P.decide(turn(tier, 0.95, event=ev), {**P.initial_state(), "mode": mode, "pending_offer": "cbt"})
    ok &= d.action == "CRISIS" and d.next_mode == "crisis" and d.state["pending_offer"] is None
check("R1: HIGH/CRITICAL -> CRISIS from every mode and event, pending offer cancelled", ok)

# ---- R2 crisis exit via the verification conversation, at any tier
d = run([turn("HIGH", 0.8, now=0), turn("LOW", 0.1, now=60), turn("LOW", 0.1, now=120)])
check("R2: a score drop alone does not end the crisis conversation", [x.action for x in d][1:] == ["STAY_IN_CRISIS"] * 2)
d = run([turn("HIGH", 0.8, now=0), turn("HIGH", 0.8, event="crisis_resolved", now=60, path="misunderstanding")])
check("R2: 'misunderstanding' can end the crisis even while still scored HIGH (no trap)",
      d[1].action == "EXIT_TO_CHAT" and d[1].next_mode == "chat")
check("R2: every path schedules the 24 h follow-up (UX Flow 4)", d[1].state["follow_up_due_ts"] == 60 + DAY)
check("R2: HIGH-only crisis does not pin helplines", d[1].state["pin_helplines"] is False)
d = run([turn("CRITICAL", 0.95, now=0), turn("MODERATE", 0.5, now=30),
         turn("LOW", 0.2, event="crisis_resolved", now=60, path="reached_out")])
check("R2: a crisis that reached CRITICAL pins the helplines after exit", d[-1].state["pin_helplines"] is True)
again = P.decide(turn("HIGH", 0.8, now=90), d[-1].state)
check("R2: a later HIGH turn reopens the crisis as usual", again.action == "CRISIS")
check("R2: crisis_resolved without a valid path raises",
      raises(lambda: P.decide(turn("LOW", event="crisis_resolved"), {**P.initial_state(), "mode": "crisis"})))

# ---- R3 strictness
check("R3: unknown tier raises (HIGH_CRISIS until G15 decided)", raises(lambda: P.decide(turn("HIGH_CRISIS"), P.initial_state())))
check("R3: unknown event raises", raises(lambda: P.decide(turn(event="dance"), P.initial_state())))
check("R3: unknown mode raises", raises(lambda: P.decide(turn(), {**P.initial_state(), "mode": "party"})))
check("R3: score > 1 raises", raises(lambda: P.decide(turn(score=1.2), P.initial_state())))
check("R3: accept with no pending offer raises", raises(lambda: P.decide(turn(event="accept_offer"), P.initial_state())))

# ---- R4
ok = all(P.decide(turn("MODERATE", 0.69, flags=["vocal_contradiction"]), {**P.initial_state(), "mode": m}).action == "CONTINUE"
         for m in ("cbt", "grounding", "checkin"))
check("R4: no offers while in cbt / grounding / checkin", ok)

# ---- R5 / R6
check("R5: sustained scores -> exactly one CBT offer", [x.action for x in run(warm())].count("OFFER_CBT") == 1)
check("R5: a single first-turn MODERATE score does not trigger CBT", run([turn("MODERATE", 0.6)])[-1].action != "OFFER_CBT")
check("R5: one isolated spike does not trigger CBT (EWMA)",
      run([turn("LOW", 0.05, now=0), turn("LOW", 0.05, now=60), turn("MODERATE", 0.6, now=120)])[-1].action != "OFFER_CBT")
check("R5: conflict flag triggers a CBT offer even at LOW score", run([turn("LOW", 0.1, flags=["vocal_contradiction"])])[-1].action == "OFFER_CBT")
st = run(warm())[-1].state
st = P.decide(turn(event="decline_offer", now=10), st).state      # -> grounding alternative (R7)
st = P.decide(turn(event="decline_offer", now=20), st).state      # decline that too
check("R6: no new CBT offer while the score stays high (not re-armed)",
      run([turn("MODERATE", 0.6, now=DAY + 100)], st)[-1].action != "OFFER_CBT")
dip = run([turn("LOW", 0.0, now=DAY + 200 + i) for i in range(3)] +
          [turn("MODERATE", 0.9, now=DAY + 600), turn("MODERATE", 0.9, now=DAY + 700)], st)
check("R6: re-arms after dipping below DISARM, then offers again", "OFFER_CBT" in [x.action for x in dip])

# cooldowns
d = run([turn("LOW", 0.1, flags=["vocal_contradiction"], now=0)])[-1]
st = P.decide(turn(event="decline_offer", now=1), d.state).state
st = P.decide(turn(event="decline_offer", now=2), st).state
check("cooldown blocks a second CBT offer within 24 h", P.decide(turn("LOW", 0.1, flags=["vocal_contradiction"], now=3 * H), st).action != "OFFER_CBT")
check("CBT offer allowed again after 24 h", P.decide(turn("LOW", 0.1, flags=["vocal_contradiction"], now=DAY + 5), st).action == "OFFER_CBT")
st = {**P.initial_state(), "cbt_declines": 2, "last_cbt_offer_ts": 0.0}
check("2 declines: still blocked at 48 h", P.decide(turn("LOW", 0.1, flags=["vocal_contradiction"], now=48 * H), st).action != "OFFER_CBT")
check("2 declines: allowed at 72 h", P.decide(turn("LOW", 0.1, flags=["vocal_contradiction"], now=72 * H), st).action == "OFFER_CBT")

# ---- R7 / R8 offer conversation stays open
d = run(warm())[-1]
check("CBT offered once 3 turns of scores are above ARM", d.action == "OFFER_CBT")
w = P.decide(turn(event="ask_what_is_it", now=5), d.state)
check("R8: 'what is it' explains and keeps the offer open", w.action == "EXPLAIN_OFFER" and w.state["pending_offer"] == "cbt")
acc = P.decide(turn(event="accept_offer", now=6), w.state)
check("accept after explanation -> ENTER_CBT", acc.action == "ENTER_CBT" and acc.next_mode == "cbt")
dec = P.decide(turn(event="decline_offer", now=6), d.state)
check("R7: CBT decline -> one alternative offered (never a dead end)", dec.action == "OFFER_GROUNDING" and dec.state["cbt_declines"] == 1)
capped = {**d.state, "offer_times": [0.0, 1.0, 2.0], "last_grounding_offer_ts": 3.0}
check("R7: the alternative is a reply, so cooldown/cap do not block it", P.decide(turn(event="decline_offer", now=7), capped).action == "OFFER_GROUNDING")
check("end_mode leaves cbt -> chat", P.decide(turn(event="end_mode", now=9), acc.state).next_mode == "chat")
check("'what is it' with no pending offer raises", raises(lambda: P.decide(turn(event="ask_what_is_it"), P.initial_state())))

# grounding offers
g = P.decide(turn("MODERATE", 0.45, now=H), {**P.initial_state(), "last_cbt_offer_ts": 0.0, "armed": False})
check("MODERATE turn with CBT on cooldown -> grounding offer", g.action == "OFFER_GROUNDING")
check("grounding offer respects its 2 h cooldown", P.decide(turn("MODERATE", 0.45, now=H + 60), {**g.state, "pending_offer": None}).action != "OFFER_GROUNDING")
lap = run([turn("MODERATE", 0.55, now=0), turn("LOW", 0.0, now=60)])
check("an unanswered offer lapses and is not a decline", lap[1].state["pending_offer"] is None and lap[1].state["cbt_declines"] == 0)

# ---- R9 daily cap
st = {**P.initial_state(), "offer_times": [0.0, 10.0, 20.0]}
check("R9: no 4th system offer within 24 h", P.decide(turn("MODERATE", 0.6, flags=["vocal_contradiction"], now=30), st).action == "CONTINUE")
check("R9: cap window rolls after 24 h", P.decide(turn("MODERATE", 0.6, flags=["vocal_contradiction"], now=DAY + 30), st).action == "OFFER_CBT")
check("R9: crisis is never capped", P.decide(turn("HIGH", 0.8, now=30), st).action == "CRISIS")

# simple entries
check("LOW, nothing else -> CONTINUE", P.decide(turn("LOW"), P.initial_state()).action == "CONTINUE")
check("user can start an exercise directly", P.decide(turn(event="start_grounding"), P.initial_state()).next_mode == "grounding")
check("scheduled check-in enters checkin mode", P.decide(turn(event="start_checkin"), P.initial_state()).next_mode == "checkin")

# purity
st = {**P.initial_state(), "scores": [0.2] * 25}
snap = copy.deepcopy(st)
a = P.decide(turn("MODERATE", 0.5, now=1), st)
b = P.decide(turn("MODERATE", 0.5, now=1), st)
check("decide() never mutates the input state", st == snap)
check("decide() is deterministic", a.action == b.action and a.state == b.state)
check(f"score history capped at {P.HISTORY_MAX}", len(a.state["scores"]) == P.HISTORY_MAX)

# invariants
ok = True
n = 0
for mode, tier, ev, pend in itertools.product(P.MODES, P.TIERS, P.EVENTS, (None, "cbt", "grounding")):
    st = {**P.initial_state(), "mode": mode, "pending_offer": pend, "scores": [0.5, 0.6]}
    t = turn(tier, 0.55, event=ev, now=10 * DAY, path="misunderstanding")
    n += 1
    try:
        d = P.decide(t, st)
    except ValueError:
        ok &= (ev in ("accept_offer", "decline_offer", "ask_what_is_it") and (pend is None or mode != "chat")
               and mode != "crisis" and tier not in P.CRISIS_TIERS)
        continue
    ok &= d.next_mode in P.MODES
    if not (mode == "crisis" and ev == "crisis_resolved"):
        ok &= (tier in P.CRISIS_TIERS) == (d.action == "CRISIS")
    ok &= not (d.action.startswith("OFFER") and mode != "chat")
    ok &= not (mode == "crisis" and ev != "crisis_resolved" and d.next_mode != "crisis")
check(f"invariants over all mode x tier x event x pending combos ({n} cases)", ok)

print("\nALL PASSED" if not fails else "\nFAILED: " + ", ".join(fails))
sys.exit(1 if fails else 0)
