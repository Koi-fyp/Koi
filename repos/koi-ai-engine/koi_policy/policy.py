"""
KOI turn policy: CBT-offer trigger (gap G2) + mode routing (gap G3). Oct 14-15 2026.

STATUS: DRAFT by Claude. Not canon, not clinically validated, not wired to any endpoint.
Where a number has a published source it is cited next to it; every other number is an ENGINEERING DEFAULT
with no clinical source, disclosed as such (see NUMBERS in exercises.json and the README).

What it is: one pure function, decide(turn, state) -> Decision. No I/O, no model, no hidden memory.
The AI engine is stateless (Blueprint §4.1), so everything that persists across turns lives on the CLIENT and is
sent in with each turn; decide() returns the updated state for the client to store.

What it is NOT: retrieval/RAG. It never writes intervention_content; it only says "go to crisis".

Rules (all unit-tested). Ahmad, Oct 15: where options differed, prefer the ones that keep the conversation open.
  R1  HIGH or CRITICAL on this turn -> CRISIS from ANY mode, cancelling any offer or exercise.
  R2  Crisis ends only on the client event "crisis_resolved" (the end of UX Flow 4's three-path verification
      conversation), at ANY tier, so the "this was a misunderstanding" path cannot trap the user. Safeguards:
      a crisis that reached CRITICAL pins the helplines in chat for the session; every path schedules the 24-hour
      follow-up (UX Flow 4); any later HIGH/CRITICAL turn reopens the crisis as usual (R1).
  R3  Unknown tier / mode / event / crisis path, or a score outside [0, 1] -> ValueError. Nothing is guessed.
  R4  No offers outside plain chat.
  R5  CBT offer: (smoothed score >= ARM_SCORE over >= MIN_SCORES_FOR_CBT turns, trigger armed) OR a conflict flag;
      AND the CBT cooldown passed; AND the daily offer cap not reached.
  R6  After an offer the trigger disarms; it re-arms only after the smoothed score falls below DISARM_SCORE.
  R7  CBT declined -> one alternative is ALWAYS offered (grounding), with "just keep talking" as an equal choice in
      the UI, so a "no" never ends the conversation (UX Flow 5 spirit). It answers the user's "no", so it is not
      blocked by the grounding cooldown or the daily cap. 2+ CBT declines -> longer CBT cooldown.
  R8  "What is it?" on a pending offer explains it and keeps the offer open (UX Flow 10 branch).
  R9  At most DAILY_OFFER_CAP system offers per rolling 24 h (Morrison et al. 2017: up to 3/day did not lower
      response rates; the authors note "several notifications per day may be unacceptable").
"""
from dataclasses import dataclass, field

# ---- vocabulary --------------------------------------------------------------------------------------
TIERS = ("LOW", "MODERATE", "HIGH", "CRITICAL")
TIER_ALIASES = {}            # gap G15 (enum strings) is OPEN; e.g. {"HIGH_CRISIS": "HIGH"} once decided
CRISIS_TIERS = {"HIGH", "CRITICAL"}

MODES = ("chat", "checkin", "cbt", "grounding", "plan", "crisis")   # "plan": UX Flow 12 task planning (director)
EVENTS = ("none", "accept_offer", "decline_offer", "ask_what_is_it", "end_mode", "start_checkin",
          "start_grounding", "start_plan", "crisis_resolved")
CRISIS_PATHS = ("reached_out", "said_but_did_not", "misunderstanding")      # UX Flow 4's three paths

# Conflict flags that may trigger a CBT offer (UX Flow 10: "text/video conflict signal").
# PROVISIONAL: only "vocal_contradiction" is named in canon (Blueprint §4.1 example); the crisis engine's
# text-vs-video flag has no name yet. Replace/extend this set once it does.
CONFLICT_FLAGS = frozenset({"vocal_contradiction"})

# ---- parameters ---------------------------------------------------------------------------------------
ARM_SCORE = 0.40              # SOURCED: lower bound of the MODERATE band, Blueprint §4.1
DAILY_OFFER_CAP = 3           # SOURCED (frequency evidence): Morrison et al. 2017, PLOS ONE (see R9)
CBT_COOLDOWN = 24 * 3600      # SOURCED (loosely): "daily" schedule in Morrison et al. 2017 had no response-rate penalty
FOLLOW_UP_AFTER = 24 * 3600   # SOURCED: UX Flow 4 "24-hour follow-up"
# ENGINEERING DEFAULTS (no clinical source exists for these; disclosed):
EWMA_ALPHA = 0.3
HISTORY_MAX = 20
MIN_SCORES_FOR_CBT = 3
DISARM_SCORE = 0.30
CBT_COOLDOWN_AFTER_DECLINES = 72 * 3600
DECLINES_FOR_LONG_COOLDOWN = 2
GROUNDING_COOLDOWN = 2 * 3600
DAY = 24 * 3600


@dataclass
class Decision:
    action: str   # CRISIS | STAY_IN_CRISIS | OFFER_CBT | OFFER_GROUNDING | EXPLAIN_OFFER | ENTER_CBT |
                  # ENTER_GROUNDING | ENTER_PLAN | ENTER_CHECKIN | EXIT_TO_CHAT | CONTINUE
    next_mode: str
    state: dict   # NEW state for the client to store (input is never mutated)
    smoothed_score: float | None
    reasons: list = field(default_factory=list)


def initial_state():
    return {"mode": "chat", "scores": [], "pending_offer": None, "last_cbt_offer_ts": None,
            "last_grounding_offer_ts": None, "cbt_declines": 0, "armed": True, "offer_times": [],
            "crisis_peak": None, "pin_helplines": False, "follow_up_due_ts": None, "last_crisis_path": None}


def parse_tier(tier):
    t = TIER_ALIASES.get(tier, tier)
    if t not in TIERS:
        raise ValueError(f"unknown risk_category {tier!r}; expected one of {TIERS} (enum is gap G15)")
    return t


def ewma(scores, alpha=EWMA_ALPHA):
    s = None
    for x in scores:
        s = x if s is None else alpha * x + (1 - alpha) * s
    return s


def _cooldown_passed(last_ts, now, gap):
    return last_ts is None or now - last_ts >= gap


def decide(turn, state):
    """turn: {"tier", "score": float|None, "flags": [..], "event", "now": epoch s, "crisis_path": optional}
    state: client-held dict (see initial_state). Returns Decision; never mutates `state`."""
    tier = parse_tier(turn["tier"])
    score = turn.get("score")
    flags = set(turn.get("flags") or [])
    event = turn.get("event", "none")
    now = float(turn["now"])
    if event not in EVENTS:
        raise ValueError(f"unknown event {event!r}")
    if score is not None and not (0.0 <= float(score) <= 1.0):
        raise ValueError(f"score {score!r} outside [0, 1]")
    st = {**initial_state(), **state}
    st["scores"] = list(st["scores"])
    st["offer_times"] = [t for t in st["offer_times"] if now - t < DAY]
    if st["mode"] not in MODES:
        raise ValueError(f"unknown mode {st['mode']!r}")

    if score is not None:
        st["scores"] = (st["scores"] + [float(score)])[-HISTORY_MAX:]
    sm = ewma(st["scores"])
    mode = st["mode"]
    why = []

    def out(action, next_mode, *reasons):
        st["mode"] = next_mode
        return Decision(action, next_mode, st, sm, why + list(reasons))

    def offer(kind, reason):
        st["pending_offer"] = kind
        st["offer_times"] = st["offer_times"] + [now]
        st["last_" + ("cbt" if kind == "cbt" else "grounding") + "_offer_ts"] = now
        return out("OFFER_" + kind.upper(), mode, reason)

    cap_ok = len(st["offer_times"]) < DAILY_OFFER_CAP

    # R2: explicit end of the crisis conversation, at any tier
    if mode == "crisis" and event == "crisis_resolved":
        path = turn.get("crisis_path")
        if path not in CRISIS_PATHS:
            raise ValueError(f"crisis_resolved needs crisis_path in {CRISIS_PATHS}, got {path!r}")
        peak = "CRITICAL" if tier == "CRITICAL" else st["crisis_peak"]
        st.update(pin_helplines=st["pin_helplines"] or peak == "CRITICAL", crisis_peak=None,
                  follow_up_due_ts=now + FOLLOW_UP_AFTER, last_crisis_path=path)
        return out("EXIT_TO_CHAT", "chat", f"R2: crisis conversation completed via '{path}' at tier {tier}; "
                   "follow-up scheduled" + ("; helplines pinned" if st["pin_helplines"] else ""))

    # R1: crisis preempts everything
    if tier in CRISIS_TIERS:
        st["pending_offer"] = None
        st["crisis_peak"] = "CRITICAL" if "CRITICAL" in (tier, st["crisis_peak"]) else "HIGH"
        return out("CRISIS", "crisis", f"R1: tier {tier} preempts mode {mode!r}")
    if mode == "crisis":
        return out("STAY_IN_CRISIS", "crisis", "R2: crisis conversation not completed yet")

    if sm is not None and sm < DISARM_SCORE:                          # R6 bookkeeping
        st["armed"] = True

    if mode != "chat" and st["pending_offer"] is not None:            # offers only live in chat (R4)
        why.append(f"dropped stale pending {st['pending_offer']} offer (mode is {mode})")
        st["pending_offer"] = None
    pending = st["pending_offer"]

    if event in ("accept_offer", "decline_offer", "ask_what_is_it"):
        if pending is None:
            raise ValueError(f"{event} received but no offer is pending")
        if event == "ask_what_is_it":                                 # R8
            return out("EXPLAIN_OFFER", mode, f"R8: explaining the {pending} offer; offer stays open")
        st["pending_offer"] = None
        if event == "accept_offer":
            target = "cbt" if pending == "cbt" else "grounding"
            return out("ENTER_" + target.upper(), target, f"user accepted {pending} offer")
        if pending == "cbt":                                          # R7
            st["cbt_declines"] += 1
            # a reply to the user's "no", not an unsolicited offer: not blocked by the grounding cooldown or the cap
            return offer("grounding", "R7: CBT declined; offering grounding or 'just keep talking'")
        return out("CONTINUE", mode, f"user declined {pending} offer; conversation continues")

    if event == "end_mode":
        return out("EXIT_TO_CHAT", "chat", f"user ended {mode}")
    if event == "start_grounding":
        st["pending_offer"] = None
        return out("ENTER_GROUNDING", "grounding", "user started an exercise directly")
    if event == "start_plan":
        st["pending_offer"] = None
        return out("ENTER_PLAN", "plan", "user started task planning (UX Flow 12)")
    if event == "start_checkin":
        st["pending_offer"] = None
        return out("ENTER_CHECKIN", "checkin", "scheduled check-in started (UX Flow 2)")

    if mode != "chat":                                                # R4
        return out("CONTINUE", mode, f"R4: in {mode}; no offers")
    if pending is not None:
        why.append(f"{pending} offer lapsed (user kept chatting)")
        st["pending_offer"] = None

    if not cap_ok:                                                    # R9
        return out("CONTINUE", mode, f"R9: daily offer cap ({DAILY_OFFER_CAP}) reached")

    gap = CBT_COOLDOWN_AFTER_DECLINES if st["cbt_declines"] >= DECLINES_FOR_LONG_COOLDOWN else CBT_COOLDOWN
    conflict = bool(flags & CONFLICT_FLAGS)
    armed_hit = st["armed"] and len(st["scores"]) >= MIN_SCORES_FOR_CBT and sm is not None and sm >= ARM_SCORE
    if (armed_hit or conflict) and _cooldown_passed(st["last_cbt_offer_ts"], now, gap):   # R5
        st["armed"] = False
        return offer("cbt", "R5: " + ("conflict flag " + ",".join(sorted(flags & CONFLICT_FLAGS)) if conflict
                                      else f"smoothed score {sm:.2f} >= {ARM_SCORE}"))

    if tier == "MODERATE" and _cooldown_passed(st["last_grounding_offer_ts"], now, GROUNDING_COOLDOWN):
        return offer("grounding", "MODERATE tier; grounding cooldown passed")

    if sm is None:
        why.append("no scores yet; no score-based offer possible")
    return out("CONTINUE", mode, "no rule fired")


def record_score(state, score):
    """Score bookkeeping for turns where decide() is not called (e.g. mid-exercise steps handled by the director).
    Same history cap as decide(); never changes mode, offers or crisis state."""
    st = {**initial_state(), **state}
    if score is not None:
        if not (0.0 <= float(score) <= 1.0):
            raise ValueError(f"score {score!r} outside [0, 1]")
        st["scores"] = (list(st["scores"]) + [float(score)])[-HISTORY_MAX:]
    return st
