# koi_policy — G2 (CBT-offer trigger), G3 (mode routing), G5 + exercise catalogue (v3) + exercise director (v4)

> **v4 (Oct 15, late):** exercises now happen **inside the normal chat**, spoken by the companion. See *Exercise director (v4)* at the end. The standalone page (`breathing_template.html`, `build_reference.py`, `breathing_reference.html`, `test_breathing_ui.py`) is **retired as the product UI**: it was a form-like screen, which UX Flow 10 rules out. Keep it only as a reference for the breathing animation timing.

Draft by Claude, Oct 15 2026. Not canon, not clinically reviewed, not wired into any endpoint or client.
Separate from `koi_rag`: none of this is retrieval, and nothing here changes `intervention_content`.

## Files
| File | What |
|---|---|
| `policy.py` | `decide(turn, state)`: WHETHER to offer / enter / exit (rules R1-R9). |
| `catalogue.py` | Validates the catalogue + translations; `eligible()` = WHICH exercises; `localize()` = language. |
| `exercises.json` | 12 exercises in 4 families, each with source, UX-flow mapping, "what is it", safety rules; `NUMBERS` lists every number with its source or "engineering default". |
| `exercises_i18n.json` (built by `build_i18n.py`) | Urdu script (`ur`) and Roman Urdu with English code-switching (`ur-roman`) for every user-facing string, plus UI strings. |
| `breathing_template.html` + `build_reference.py` -> `breathing_reference.html` | Trilingual reference UI (RTL for Urdu). |
| `test_policy.py` (44), `test_catalogue.py` (34), `test_breathing_ui.py` (56) | All passing in the sandbox. |
| `simulate.py` | Decision trace for a scripted synthetic conversation. |

Run: `python test_policy.py`, `python test_catalogue.py`, `python build_i18n.py`, `python build_reference.py`, `python test_breathing_ui.py` (Playwright + Chromium).

## Numbers (all disclosed in `exercises.json` -> `NUMBERS`)
| Number | Value | Source |
|---|---|---|
| Slow breathing pace | 6/min (4 s in, 6 s out) | Lehrer & Gevirtz 2014 (resonance ~0.1 Hz); Zaccaro et al. 2018 (<10/min) |
| Longer exhale | 6 s vs 4 s | Weak: RCT found no significant ratio effect (d=0.2); kept per WHO DWM "breathe out slowly" |
| Session length | 1 or 5 min | Balban et al. 2023 RCT: 5 min/day |
| Cyclic sighing | 2 s + 1 s in, 6 s out | Pattern: Balban 2023; seconds estimated under 10/min |
| Action-plan confidence | 0-10, below 7 -> make it smaller | Brief Action Planning |
| Social Ladder distress | SUDS 0-100, steps ≤10 apart | Wolpe |
| Thought belief | 0-100 | CBT thought-record convention (not re-verified) |
| Offers per day | max 3 | Morrison et al. 2017 |
| CBT cooldown | 24 h | loosely Morrison et al. 2017 (daily) |
| MODERATE threshold | 0.40 | Blueprint §4.1 |
| EWMA 0.3, disarm 0.30, min 3 turns, 72 h, 2 h, mood 1-5 | — | **Engineering defaults, no clinical source** |

## Decisions applied (Ahmad, Oct 15: "less closed pool, fewer ended discussions")
- **R2** Crisis ends on the verification conversation at any tier (no trap). CRITICAL pins helplines; every path schedules the 24 h follow-up; later HIGH reopens.
- **E2** Crisis modal at HIGH: slow breathing, grounding, 5-4-3-2-1, below the helplines, never auto-started. Nothing at CRITICAL.
- **R7** CBT "no" always gets one alternative plus "just keep talking"; not blocked by cooldown/cap.
- **R8** "What is it?" keeps the offer open.
- **R9** Daily cap of 3 offers.
- Every decline branch and every post-check has a way to keep talking; mood check is optional.

## Languages
English is the default. `ur` and `ur-roman` are Claude's drafts, **pending native review** (align with WHO's Urdu PM+ / Urdu THP). The companion speaks in the masculine first person ("پوچھوں گا" / "poochunga"), matching the male default avatar (UX Flow 1); a female avatar needs the feminine forms. User-side verbs are written "raha/rahi".

## Client state contract (engine is stateless)
`mode`, `scores` (last 20), `pending_offer`, `last_cbt_offer_ts`, `last_grounding_offer_ts`, `cbt_declines`, `armed`, `offer_times`, `crisis_peak`, `pin_helplines`, `follow_up_due_ts`, `last_crisis_path`. Per turn: `tier`, `score`, `flags`, `event`, `now`, and `crisis_path` with `crisis_resolved`.

## Open dependencies
G14 (per-turn scores from `/chat`), G15 (enum), G6, G8 (Flow 4 verification text), where the policy runs, clinician review, native Urdu review, female-avatar Urdu forms.

## Do not claim
That triggers are tuned or validated, that exercises are clinically reviewed or WHO-endorsed, that the Urdu is reviewed, or that any of this is wired into the app.


---

## Exercise director (v4, Oct 15 2026) — "the avatar just talks"

What the user sees: the companion offers, explains, guides and checks in, in the main chat, in English, Urdu script
or Roman Urdu. Only the breathing animation (UX Flow 5) appears, and it is the avatar breathing, started by the
director. What runs underneath, every turn:

| # | Piece | File |
|---|---|---|
| 1 | Signed client-carried state (engine stays stateless). Edits are detected; replay of an old token is not (disclosed). | `state_token.py` |
| 2 | **Distress pre-check before anything is written (choice A).** Stops the exercise, hands the turn to the companion, asks the backend to prioritise the risk check. TSD still runs in the background exactly as locked (Gate 1b-concurrency). | `intents.distress` |
| 3 | Latest TSD tier HIGH/CRITICAL -> crisis (policy R1); `on_risk()` for a background result mid-exercise. | `director.py` |
| 4 | Step-aware intent reading with abstention: only intents the current step can accept; ask again (max 2) instead of guessing. Lexicon (longest phrase wins, punctuation and "but/lekin" respected) + char-trigram kNN for misspellings. Encoder is swappable (e5 later). | `intents.py` |
| 5 | Plain state machine over reviewed steps: breathing, grounding (WHO DWM), task planning (PM+ / Brief Action Planning), CBT offer. | `journeys.json`, `director.py` |
| 6 | **Reply = short LLM acknowledgement + fixed reviewed line (choice B).** Each LLM sentence is checked when complete and released only if it passes (same granularity as canon's per-sentence TTS); 1 retry, then a reviewed fallback. No question, number, timing, breathing instruction, diagnosis or "you look calmer" from the LLM. Avatar emotion limited to canon's 5 (calm ones in exercises). | `compose.py` |
| 7 | UI actions only from the director: `start_breathing` (4 s in / 6 s out, cue audio per language), `pause_breathing`, `resume_breathing`, `stop_breathing`, `save_go_to`, `save_task`. | `director.py` |
| 8 | Fail closed: risk check unavailable -> no offers and no exercise started. | `director.py` |

Event order per turn: urgent UI (stop/pause) -> `companion_state` -> sentences -> UI -> `handoff` -> `state` (new token).
`handoff` = the director has nothing to say this turn: `companion` (normal reply), `crisis` (UX Flow 4), `cbt_module` (not built).

Run: `python test_director.py` (71 checks) and `python demo_conversation.py` (3 scripted conversations, stub LLM).
Also re-run `python test_policy.py` (policy gained mode `plan` / event `start_plan` and `record_score`).

### Backend adapter (to write against the real model)
`phrase_fn(direction) -> (companion_state, tokens)`: put `compose.direction_prompt(direction)` into the system prompt
for that call, generate `{companion_state, reply}` with vLLM structured outputs, stream the `reply` tokens.
The `/api/v1/chat` contract needs two additions (decision for the backend owner): `exercise_state` (the signed
token) in request and response, and the `ui_action` / `handoff` events. Web/Flutter need `AvatarController.breathe(...)`
(or equivalent) and pre-rendered cue audio with Rhubarb mouth cues.

### Honest limits
- Tested only with a stub LLM. How the real fine-tuned Qwen3-4B acknowledgements read is **unknown** until run.
- Intent held-out set (39 items) is written by Claude, not by users; one label was corrected after the first run
  (my mislabel: "ye kya hota hai" does mean "what is it"). Not independent evidence.
- Distress lexicon is a cheap early stop, not a detector of record; misses are expected. TSD is the safety net.
- Fixed lines in all three languages are Claude's drafts: **no clinician review, no native Urdu review.**
- Thresholds (kNN similarity 0.45 / 0.6, vote share 0.6, 2 repairs, 5-word lapse) are engineering defaults.
- Thought reflection (CBT steps), Social Ladder (Flow 11) and check-in (Flow 2) journeys are not built yet.
