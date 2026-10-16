"""Print a decision trace for a scripted (synthetic) conversation. Demo/explanation aid, not evidence.
    python simulate.py"""
import policy as P

M = 60
SCRIPT = [  # (minute, tier, score, flags, event, what the user does)
    (0, "LOW", 0.10, [], "none", "casual chat"),
    (2, "LOW", 0.25, [], "none", "mentions a bad week"),
    (4, "MODERATE", 0.55, [], "none", "low mood"),
    (5, "MODERATE", 0.55, [], "none", "ignores the breathing offer, keeps talking"),
    (6, "MODERATE", 0.65, [], "none", "low mood continues"),
    (7, "MODERATE", 0.60, [], "decline_offer", "says no to CBT"),
    (8, "MODERATE", 0.58, [], "start_grounding", "taps the breathing button themselves"),
    (12, "LOW", 0.30, [], "end_mode", "finishes breathing"),
    (20, "HIGH", 0.82, [], "none", "says something alarming"),
    (22, "MODERATE", 0.45, [], "none", "calmer, still in crisis flow"),
    (25, "LOW", 0.20, [], "crisis_resolved", "completes the crisis flow (UX Flow 4), path: misunderstanding"),
    (30, "LOW", 0.10, ["vocal_contradiction"], "none", "says 'I'm fine', voice disagrees -- no offer: CBT cooldown (24 h) still running"),
]
st = P.initial_state()
print(f"{'min':>3}  {'tier':8} {'score':>5} {'ewma':>5}  {'event':16} {'action':16} mode       why")
for minute, tier, score, flags, event, note in SCRIPT:
    d = P.decide({"tier": tier, "score": score, "flags": flags, "event": event, "now": minute * M,
                  "crisis_path": "misunderstanding"}, st)
    st = d.state
    print(f"{minute:>3}  {tier:8} {score:>5.2f} {d.smoothed_score:>5.2f}  {event:16} {d.action:16} {d.next_mode:10} "
          f"{'; '.join(d.reasons)}   [{note}]")
