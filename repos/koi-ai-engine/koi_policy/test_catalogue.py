"""Tests for exercises.json + catalogue.py.   Run: python test_catalogue.py"""
import copy
import sys

import catalogue as C
import policy as P

fails = []


def check(n, c):
    print(("PASS " if c else "FAIL ") + n)
    if not c:
        fails.append(n)


def raises(fn):
    try:
        fn()
    except ValueError:
        return True
    return False


cat = C.load()
ex = {e["id"]: e for e in cat["exercises"]}

check("catalogue validates with no problems", C.validate(cat) == [])
check("every exercise names a source and a licence", all(e["source"].strip() and e["licence"].strip() for e in ex.values()))
check("every exercise is marked draft via catalogue review_status", cat["review_status"] == "draft-unreviewed")
check("every exercise has a 'what is it' text (UX Flow 10 branch)", all(e["what_is_it"].strip() for e in ex.values()))
check("every exercise maps to at least one locked UX flow", all(e["ux_flows"] for e in ex.values()))
check("every exercise has an activity_type for the jigsaw (UX Flow 6)",
      all(e["activity_type"] in {"calm", "mind", "activity", "connection"} for e in ex.values()))

# E1/E2/E3 eligibility
ok = all(C.eligible(cat, "CRITICAL", ctx) == [] for ctx in ("chat", "menu", "crisis_modal", "cbt_module"))
check("E1: nothing at CRITICAL in any context", ok)
check("E2: HIGH -> only crisis-modal exercises, only in the modal",
      set(C.eligible(cat, "HIGH", "crisis_modal")) == {"slow_breathing", "dwm_grounding", "grounding_54321"}
      and all(C.eligible(cat, "HIGH", c) == [] for c in ("chat", "menu", "cbt_module")))
check("E3: no system offers in the crisis modal below HIGH", C.eligible(cat, "MODERATE", "crisis_modal") == [])
mod = C.eligible(cat, "MODERATE", "chat")
check("E3: MODERATE system offers are calm/short only (no conversations, no making-room)",
      mod and all(ex[i]["type"] != "conversation" and not ex[i].get("user_initiated_only") for i in mod))
check("E4: making-room and thought-check are never system-offered",
      all(i not in C.eligible(cat, t, "chat") for t in ("LOW", "MODERATE") for i in ("dwm_making_room", "thought_check")))
check("E4: user can still choose them from the menu below HIGH", {"dwm_making_room", "thought_check"} <= set(C.eligible(cat, "LOW", "menu")))
check("E5: unknown tier raises", raises(lambda: C.eligible(cat, "HIGH_CRISIS")))
check("unknown context raises", raises(lambda: C.eligible(cat, "LOW", "lobby")))

# safety content checks
check("no breath-hold phases", all("hold" not in ph["label"].lower() for e in ex.values() for ph in e.get("phases", [])))
check("breathing safety note keeps the dizziness instruction", "dizzy" in cat["safety_note"])
check("slow breathing is ~6 breaths/min (sourced pace)", 60 / sum(p["seconds"] for p in ex["slow_breathing"]["phases"]) == 6)
check("every breathing pattern stays under 10 breaths/min (Zaccaro 2018)",
      all(60 / sum(p["seconds"] for p in e["phases"]) < 10 for e in ex.values() if e["type"] == "paced_breathing"))
check("breathing offers a 5-minute option (Balban 2023)",
      all(any(o["cycles"] * sum(p["seconds"] for p in e["phases"]) >= 297 for o in e["duration_options"])
          for e in ex.values() if e["type"] == "paced_breathing"))
check("action plans use 0-10 confidence with the < 7 rule (Brief Action Planning)",
      all(e["if_commitment_below"]["value"] == 7 and any(p["key"] == "commitment" and p["answer"] == "number_0_10" for p in e["prompts"])
          for e in ex.values() if "if_commitment_below" in e))
check("Social Ladder rule: SUDS 0-100, max 10 between steps (Wolpe)", ex["pmplus_social_support"]["ladder_rules"]["max_gap_between_steps"] == 10)
check("every number is listed with a status and source", all(n["status"] and n["source"] for n in cat["NUMBERS"]))
check("thought, problem and making-room exercises carry a stop rule",
      all(ex[i].get("stop_if") for i in ("thought_check", "pmplus_managing_problems", "dwm_making_room")))
check("social-support exercise forbids pushing contact with unsafe people", "never push contact" in ex["pmplus_social_support"]["safety"].lower())
check("decline follow-up never just closes: every branch offers an exercise",
      all(a.get("offer_exercises") for a in cat["decline_followup"]["alternatives"].values()))
check("post-check always offers 'Keep talking' (no dead end)", bool(cat["post_check"]["keep_talking"]))
check("post-check is a 1-5 mood rating with a low-mood path",
      cat["post_check"]["scale"] == {"min": 1, "max": 5, "min_label": "Very low", "max_label": "Very good"} and cat["post_check"]["on_low"])

# validator actually catches problems (not vacuous)
bad = copy.deepcopy(cat)
B = {e["id"]: e for e in bad["exercises"]}
B["slow_breathing"]["phases"].append({"label": "Hold", "seconds": 4, "animate": "none"})
B["dwm_grounding"]["steps"].append("Take your tablets now.")
B["grounding_54321"]["offer_when"] = ["CRITICAL"]
B["dwm_making_room"]["crisis_modal_ok"] = True
bad["decline_followup"]["alternatives"]["Not the right moment"]["offer_exercises"] = ["nope"]
errs = " | ".join(C.validate(bad))
check("validator catches hold phase, veto word, CRITICAL offer, unsafe modal exercise, dangling alternative",
      all(s in errs for s in ("breath-hold", "veto dosing", "offer_when may only", "crisis modal", "unknown exercise nope")))

# policy <-> catalogue agree: whenever policy offers grounding, the catalogue has something to offer
ok = True
for tier in ("LOW", "MODERATE"):
    st = {**P.initial_state(), "last_cbt_offer_ts": 0.0, "armed": False}
    d = P.decide({"tier": tier, "score": 0.5, "flags": [], "event": "none", "now": 10.0 ** 6}, st)
    if d.action == "OFFER_GROUNDING":
        ok &= bool(C.eligible(cat, tier, "chat"))
check("whenever policy offers grounding, at least one catalogue exercise is eligible", ok)

# languages
i18n = C.load_i18n()
check("every English string has an Urdu-script and Roman Urdu translation of the same shape", C.validate_i18n(cat, i18n) == [])
check("localized catalogues still pass every structural/safety rule", all(C.validate(C.localize(cat, i18n, l)) == [] for l in C.LANGS))
check("Urdu text is in Urdu script; Roman Urdu is Latin with English code-switching",
      "\u0627" <= C.localize(cat, i18n, "ur")["offer"]["text"][0] <= "\u06ff" and "exercise" in C.localize(cat, i18n, "ur-roman")["offer"]["text"])
bad_i = copy.deepcopy(i18n)
bad_i["ur"]["exercises"]["dwm_grounding"]["steps"].pop()
bad_i["ur-roman"]["exercises"]["slow_breathing"]["intro"] = "zehr"
errs_i = " | ".join(C.validate_i18n(cat, bad_i))
check("i18n validator catches a missing step and a veto term", "dwm_grounding.steps" in errs_i and "veto term" in errs_i)
check("unknown language raises", raises(lambda: C.localize(cat, i18n, "fr")))

print("\nALL PASSED" if not fails else "\nFAILED: " + ", ".join(fails))
sys.exit(1 if fails else 0)
