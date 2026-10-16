# Section F — P1 Chat Service

## Starting hash
Command: `E:\Setups\anaconda\envs\koivenv\python.exe -c "hashlib.sha256(open(p,'rb').read().replace(b'\\r\\n',b'\\n')).hexdigest()[:12]"`
Raw output: `c61d7eac680b` (PASS; required `c61d7eac680b`)

## Implementation
Added/refactored:
- `deploy/modal/chat_core.py`
- `deploy/modal/stream_extract.py`
- `deploy/modal/chat_app.py`
- `deploy/modal/test_chat_contract.py`
- `deploy/modal/smoke_chat.py`

## Tests and commands
- `E:\Setups\anaconda\envs\koivenv\python.exe -m pytest deploy\modal\test_chat_contract.py -q` -> `8 passed in 0.64s`
- `E:\Setups\anaconda\envs\koivenv\python.exe test_task2.py` -> exit 0 (only pre-existing pydantic UserWarning from `app/core/config.py`)
- `E:\Setups\anaconda\envs\koivenv\python.exe -m pytest koi_policy\test_adapter_qwen.py -q` -> `4 passed, 1 warning in 0.13s`
- `E:\Setups\anaconda\envs\koivenv\python.exe -m py_compile deploy\modal\chat_core.py deploy\modal\stream_extract.py deploy\modal\chat_app.py deploy\modal\smoke_chat.py deploy\modal\test_chat_contract.py` -> exit 0
- Local fake-engine HTTP smoke -> HTTP 200, SSE order `latency`, `companion_state`, `delta`, `done`; CORS OPTIONS 200.

## Protected hashes (SHA-256 prefixes)
- `director.py` FC2D52A9E1D7
- `policy.py` 1A318EDFB932
- `intents.py` 39BE0F36A002
- `compose.py` CA135C692C52
- `journeys.json` 9C56B1366F88
- `catalogue.py` EBEEE43DB081
- `state_token.py` 2CB6BD501EB4

## Git evidence
`git --no-pager diff --stat` raw output:
```
app/api/routes.py 131 +-
app/models/schemas.py 16 +-
app/services/inference_service.py 30 +-
rag_prototype/data/processed/authoritative_chunks.jsonl 6 +-
rag_prototype/scripts/retrieval_pipeline.py 340 +-
5 files changed, 478 insertions(+), 45 deletions(-)
```
(These are unrelated pre-existing changes; preserved.) `git status --short` also reports the pre-existing modified/untracked app, rag_prototype, docs, policy, and root files. No protected file was edited and no commit was created.

## Skipped / notes
The task references three baseline scripts with expected counts 71/44/34, but no such baseline scripts are present in this checkout (only `test_task2.py` was found); they were not guessed or run. Live Modal smoke was not run (no deployment requested; no `modal serve/deploy` used). The full exercise matrix was not run against vLLM because vLLM is intentionally absent locally; fake-engine contract coverage was run. No files under `rag_prototype`, canon docs, or protected `koi_policy` files were modified.

Result: PASS-WITH-NOTES.

--- resumed 2026-10-17 ---
P1.a: git fetch origin --prune passed. Local HEAD ae5daf9 differs from origin/feat/exercise-director-modal 2923070 because local P4 commits are unpushed; no merge/reset performed.

P1.b commands: test_chat_contract 10 passed; test_crisis_core 5 passed; test_adapter_qwen 4 passed. Combined koi_policy baseline collection errored because four legacy test modules call SystemExit(0) during collection; no changes made. Required 71/44/34 named baseline scripts are absent per prior report.

P1.c: created smoke_only.bat with no deploy commands, URL extraction from live SUMMARY or args, live2 outputs. Not run: KOI_TOKEN unavailable in this session.
P1.d: created stdlib trace_check.py; checks 3 turns, SSE ordering, enum, debug/system prompt leakage, full_text and state parity. Live run not possible without token/URL.

P1.e: hygiene scan found only HEAD:.env.template and tracked .env.example/.env.template names; no private key, PEM, serviceAccount, or long API-key matches.

## Reopened P1.b evidence (2026-10-16T21:11:29Z)
``text
===== koi_policy\test_director.py EXIT 0 =====
PASS token: round trip
PASS token: edited token is rejected
PASS token: edited payload is rejected
PASS director: tampered token -> fresh state, says why
PASS token: no secret -> refuses to sign
PASS intents: held-out set 39/39 (None = should ask again)
PASS intents: 'chalo na' (please, let's) is not a 'no'
PASS intents: 'bas' inside a sentence is not 'stop'
PASS intents: Roman 'teen' is 3, not English 'ten'
PASS intents: numbers in Urdu digits and words
PASS intents: 'I hate breathing' does not start breathing
PASS intents: a short 'ok' never switches language
PASS distress: 'done with everything' is distress, 'done' is not
PASS distress: Urdu script and Roman Urdu
PASS compose: a good acknowledgement is used
PASS compose: LLM acknowledgement that asks a question -> retried once, then reviewed fallback
PASS compose: LLM acknowledgement that a number -> retried once, then reviewed fallback
PASS compose: LLM acknowledgement that claims to see the user -> retried once, then reviewed fallback
PASS compose: LLM acknowledgement that breathing instruction -> retried once, then reviewed fallback
PASS compose: LLM acknowledgement that diagnosis -> retried once, then reviewed fallback
PASS compose: LLM acknowledgement that too long -> retried once, then reviewed fallback
PASS compose: sentence gate releases the good sentence and cuts the bad one
PASS compose: English acknowledgement in an Urdu conversation -> fallback
PASS compose: model error/timeout -> reviewed fallback, no crash
PASS compose: avatar emotion limited to canon's 5 and calm ones in exercises
PASS compose: stage direction tells the model not to ask, count or observe
PASS breathing: MODERATE -> companion acknowledges, then the reviewed offer
PASS breathing: companion_state comes first, state token last
PASS breathing: 'what's that?' -> explanation, offer stays open (R8)
PASS breathing: accept -> start line, then start_breathing UI action (after the words)
PASS breathing: sourced pacing 4 s in / 6 s out, cues in the user's language
PASS breathing: policy mode is grounding while it runs
PASS breathing: playback done -> 'How are you feeling now?'
PASS breathing: better -> go-to question (UX Flow 5 'save as my go-to')
PASS breathing: yes -> saved, exercise over, back to chat
PASS breathing: 'stop' while playing -> stop_breathing is the FIRST event
PASS breathing: other words while playing -> pause first, then 'carry on or stop?'
PASS breathing: 'haan' -> resume
PASS breathing: stop button -> stopped politely
PASS decline: 'no' -> Socratic 'why not' (UX Flow 5), not a dead end
PASS decline: 'not my thing' -> alternative technique + 'just keep talking'
PASS decline: accept the alternative -> grounding starts
PASS decline: 'no' to the alternative ends it (no ping-pong)
PASS decline: 'abhi nahi' -> 'another time' in Roman Urdu (the user switched), ends
PASS repair: unclear reply -> asks again (twice, in the user's Roman Urdu), never guesses
PASS repair: third unclear reply -> leaves it, offer counted as declined
PASS lapse: user keeps chatting at an offer -> offer dropped, companion replies normally
PASS grounding: one question per turn, all five steps, then post-check
PASS grounding: feeling worse -> no go-to question, offer to talk
PASS plan: user asks -> one small thing (UX Flow 12)
PASS plan: confidence 5 (< 7) -> make it smaller (Brief Action Planning)
PASS plan: 'saat' = 7 -> plan saved with the smaller activity
PASS plan: a non-number to the 0-10 question -> asks for just a number
PASS CBT: sustained scores -> CBT offer (policy R5)
PASS CBT: 'no' -> one calm alternative (R7)
PASS CBT: 'ok' -> handed to the CBT module (thought steps are Day 2)
PASS language: Urdu script -> Urdu acknowledgement and Urdu offer
PASS language: a bare 'ok' keeps Urdu
PASS language: Roman Urdu -> Roman Urdu lines
PASS no LLM at all (scripted mode) -> reviewed fallback acknowledgement + offer still works
PASS distress at every waiting step (20 steps x 3 languages): exercise stopped before any exercise text, companion takes over, risk check prioritised
PASS HIGH tier at every waiting step (20 steps): no exercise text, crisis, breathing stopped first
PASS safety sweep is not vacuous (covers playing, offer, grounding, plan steps)
PASS background TSD result CRITICAL mid-breathing -> stop_breathing first, then crisis handoff
PASS background TSD result LOW -> nothing happens (token unchanged)
PASS risk check unavailable -> no exercise is started
PASS risk check unavailable at 'yes' -> still no exercise started
PASS risk check unavailable -> no offers
PASS every generated sentence that reached the user passes the sentence check
PASS deterministic for the same input; input turn not mutated
PASS unknown tier string raises (enum G15 still open)

ALL PASSED

===== koi_policy\test_policy.py EXIT 0 =====
PASS R1: HIGH/CRITICAL -> CRISIS from every mode and event, pending offer cancelled
PASS R2: a score drop alone does not end the crisis conversation
PASS R2: 'misunderstanding' can end the crisis even while still scored HIGH (no trap)
PASS R2: every path schedules the 24 h follow-up (UX Flow 4)
PASS R2: HIGH-only crisis does not pin helplines
PASS R2: a crisis that reached CRITICAL pins the helplines after exit
PASS R2: a later HIGH turn reopens the crisis as usual
PASS R2: crisis_resolved without a valid path raises
PASS R3: unknown tier raises (HIGH_CRISIS until G15 decided)
PASS R3: unknown event raises
PASS R3: unknown mode raises
PASS R3: score > 1 raises
PASS R3: accept with no pending offer raises
PASS R4: no offers while in cbt / grounding / checkin
PASS R5: sustained scores -> exactly one CBT offer
PASS R5: a single first-turn MODERATE score does not trigger CBT
PASS R5: one isolated spike does not trigger CBT (EWMA)
PASS R5: conflict flag triggers a CBT offer even at LOW score
PASS R6: no new CBT offer while the score stays high (not re-armed)
PASS R6: re-arms after dipping below DISARM, then offers again
PASS cooldown blocks a second CBT offer within 24 h
PASS CBT offer allowed again after 24 h
PASS 2 declines: still blocked at 48 h
PASS 2 declines: allowed at 72 h
PASS CBT offered once 3 turns of scores are above ARM
PASS R8: 'what is it' explains and keeps the offer open
PASS accept after explanation -> ENTER_CBT
PASS R7: CBT decline -> one alternative offered (never a dead end)
PASS R7: the alternative is a reply, so cooldown/cap do not block it
PASS end_mode leaves cbt -> chat
PASS 'what is it' with no pending offer raises
PASS MODERATE turn with CBT on cooldown -> grounding offer
PASS grounding offer respects its 2 h cooldown
PASS an unanswered offer lapses and is not a decline
PASS R9: no 4th system offer within 24 h
PASS R9: cap window rolls after 24 h
PASS R9: crisis is never capped
PASS LOW, nothing else -> CONTINUE
PASS user can start an exercise directly
PASS scheduled check-in enters checkin mode
PASS decide() never mutates the input state
PASS decide() is deterministic
PASS score history capped at 20
PASS invariants over all mode x tier x event x pending combos (648 cases)

ALL PASSED

===== koi_policy\test_breathing_ui.py EXIT 0 =====
PASS [no-preference] offer shown
PASS [no-preference] 'What is it?' explains (UX Flow 10 branch)
PASS [no-preference] breathing offers 1 or 5 minutes (Balban 2023)
PASS [no-preference] breathing starts with 'Breathe in'
PASS [no-preference] safety note visible
PASS [no-preference] pause freezes the countdown
PASS [no-preference] 4 s in then 'Breathe out' (6 breaths/min)
PASS [no-preference] orb contracts on exhale
PASS [no-preference] stop -> post check
PASS [no-preference] post check always offers 'Keep talking'
PASS [no-preference] mood <= 2 -> offer to talk
PASS [no-preference] 'Not the right moment' -> short alternative + later
PASS [no-preference] 'Breathing isn't for me' -> alternatives + 'Just keep talking'
PASS [no-preference] finishing steps -> mood check
PASS [no-preference] cyclic sighing: second short inhale phase
PASS [no-preference] thought check shows belief 80 -> 50
PASS [no-preference] confidence is asked 0-10
PASS [no-preference] confidence 6 (< 7) -> make it smaller (Brief Action Planning)
PASS [no-preference] unchangeable problem -> coping exercises offered
PASS [no-preference] empty required answer does not advance
PASS [no-preference] Social Ladder SUDS 0-100 asked
PASS [no-preference] no horizontal scroll at 375 px
PASS [no-preference] no JS errors
PASS [reduce] offer shown
PASS [reduce] 'What is it?' explains (UX Flow 10 branch)
PASS [reduce] breathing offers 1 or 5 minutes (Balban 2023)
PASS [reduce] breathing starts with 'Breathe in'
PASS [reduce] safety note visible
PASS [reduce] pause freezes the countdown
PASS [reduce] 4 s in then 'Breathe out' (6 breaths/min)
PASS [reduce] orb animation off
PASS [reduce] stop -> post check
PASS [reduce] post check always offers 'Keep talking'
PASS [reduce] mood <= 2 -> offer to talk
PASS [reduce] 'Not the right moment' -> short alternative + later
PASS [reduce] 'Breathing isn't for me' -> alternatives + 'Just keep talking'
PASS [reduce] finishing steps -> mood check
PASS [reduce] cyclic sighing: second short inhale phase
PASS [reduce] thought check shows belief 80 -> 50
PASS [reduce] confidence is asked 0-10
PASS [reduce] confidence 6 (< 7) -> make it smaller (Brief Action Planning)
PASS [reduce] unchangeable problem -> coping exercises offered
PASS [reduce] empty required answer does not advance
PASS [reduce] Social Ladder SUDS 0-100 asked
PASS [reduce] no horizontal scroll at 375 px
PASS [reduce] no JS errors
PASS [ur] layout switches to right-to-left
PASS [ur] offer text in Urdu script
PASS [ur] breathing phase label in Urdu
PASS [ur] post check and keep-talking in Urdu
PASS [ur] thought check first question in Urdu
PASS [ur-roman] layout back to left-to-right
PASS [ur-roman] offer in Roman Urdu with code-switching
PASS [ur-roman] decline follow-up in Roman Urdu
PASS [ur/ur-roman] no horizontal scroll at 375 px
PASS [ur/ur-roman] no JS errors

ALL PASSED

===== koi_policy\test_catalogue.py EXIT 0 =====
PASS catalogue validates with no problems
PASS every exercise names a source and a licence
PASS every exercise is marked draft via catalogue review_status
PASS every exercise has a 'what is it' text (UX Flow 10 branch)
PASS every exercise maps to at least one locked UX flow
PASS every exercise has an activity_type for the jigsaw (UX Flow 6)
PASS E1: nothing at CRITICAL in any context
PASS E2: HIGH -> only crisis-modal exercises, only in the modal
PASS E3: no system offers in the crisis modal below HIGH
PASS E3: MODERATE system offers are calm/short only (no conversations, no making-room)
PASS E4: making-room and thought-check are never system-offered
PASS E4: user can still choose them from the menu below HIGH
PASS E5: unknown tier raises
PASS unknown context raises
PASS no breath-hold phases
PASS breathing safety note keeps the dizziness instruction
PASS slow breathing is ~6 breaths/min (sourced pace)
PASS every breathing pattern stays under 10 breaths/min (Zaccaro 2018)
PASS breathing offers a 5-minute option (Balban 2023)
PASS action plans use 0-10 confidence with the < 7 rule (Brief Action Planning)
PASS Social Ladder rule: SUDS 0-100, max 10 between steps (Wolpe)
PASS every number is listed with a status and source
PASS thought, problem and making-room exercises carry a stop rule
PASS social-support exercise forbids pushing contact with unsafe people
PASS decline follow-up never just closes: every branch offers an exercise
PASS post-check always offers 'Keep talking' (no dead end)
PASS post-check is a 1-5 mood rating with a low-mood path
PASS validator catches hold phase, veto word, CRITICAL offer, unsafe modal exercise, dangling alternative
PASS whenever policy offers grounding, at least one catalogue exercise is eligible
PASS every English string has an Urdu-script and Roman Urdu translation of the same shape
PASS localized catalogues still pass every structural/safety rule
PASS Urdu text is in Urdu script; Roman Urdu is Latin with English code-switching
PASS i18n validator catches a missing step and a veto term
PASS unknown language raises

ALL PASSED

===== PROTECTED HASHES =====
koi_policy\director.py FC2D52A9E1D7
koi_policy\policy.py 1A318EDFB932
koi_policy\intents.py 39BE0F36A002
koi_policy\compose.py CA135C692C52
koi_policy\journeys.json 9C56B1366F88
koi_policy\catalogue.py EBEEE43DB081
koi_policy\state_token.py 2CB6BD501EB4
``

