# AGENTS.md — \[REPO NAME] (fill in: koi-ai-engine / koi-mobile / koi-backend/nextjs\_app)

🆕 **\[v4.26 ADDITION — Oct 12, 2026] STALE-TEXT NOTICE for any coding agent working TSD / the AI-Backend repo. Read before acting on the TSD paragraph near the end of this file. Nothing below was edited or removed.** Chat-generated; unverified until Ahmad confirms this file was swapped into the Project.

* The v4.13 addition's last TSD paragraph says "Phase 5 (A3 subspace-separation validation) has never been run … that's the actual next step". **That is stale.** Phase 5 was run on real data Sep 17–18, 2026: A3 and A2 both failed held-out validation. The working TSD architecture is **TFN (Tensor Fusion Network) + self-paced curriculum + multi-seed ensemble** (`KOI\_TSD\_POC\_PLAN\_v1.md` v1.7; Blueprint v4.18).
* **Do not implement** the A3/MISA scaffold, MFCC audio features, orthogonality loss, or dot-product + sigmoid gated fusion from older Track/Blueprint text. The encoders are `michellejieli/emotion\_text\_classifier` (text), `speechbrain/emotion-recognition-wav2vec2-IEMOCAP` (audio), ResNet-50 frozen (video).
* Next TSD steps per the PoC plan are Phase 3 (synthetic mismatch pairs), Phase 4 (eval-pipeline smoke test), Phase 6 (gate). Phases 2a/2b are independent. None is recorded as started. Formal designation of TFN as the Phase 6 architecture awaits Ahmad's confirmation.
* Do not claim crisis-detection validation anywhere: the 0.6261 (TFN) and 0.6442 (Omni zero-shot) numbers are MELD 7-class emotion proxies.
* Detail: `claude/KOI\_TSD\_ITEM9\_CLOSURE\_v1.md` §5 R4; handoff `SESSION\_HANDOFF.md` §28.

**This file is read automatically by your coding agent at session start.**
It tells the agent WHAT to build. For HOW we work (the step-by-step process,
review requirements, when to stop and check with a human), see
`docs/KOI\_TEAM\_AGENT\_WORKFLOW.md` — read that too, every session.

\---

## What this repo is

\[One or two sentences — e.g. "FastAPI backend implementing the KOI Companion
LLM, self-hosted and self-trained, no external AI APIs."]

🆕 **\[v4.6 ADDITION] Correction to the example line above:** the original example named specific disallowed libraries and required hand-rolled implementation — both superseded as of Blueprint §1 item 1 (corrected, v4.6). The only requirement carried forward into this example is **zero external AI APIs / fully self-hosted**, which remains the project's sole inviolable constraint. Standard training frameworks/libraries are permitted; fill in your repo's actual description accordingly, without re-adding a hand-rolled-only claim.

## Canonical specs — read these before implementing anything

1. `docs/KOI\_ULTIMATE\_MASTER\_BLUEPRINT\_v4\_3.md` — system-wide architecture,
crypto standard, endpoint contracts, trust boundaries
2. `docs/TRACK\_\[YOUR\_TRACK]\_v4\_3.md` — your Phase-by-Phase task list

🆕 **\[v4.5 ADDITION] Correction — items 1 and 2 above are version-stale, do not use `v4\_3` literally.** `SESSION\_HANDOFF.md` §1 (written during the v4.4 pass) claimed this section had already been corrected to use a version placeholder instead of a hardcoded version number — that correction was never actually applied to this file until now. The current canonical version, as of this writing, is **v4.5** (`KOI\_ULTIMATE\_MASTER\_BLUEPRINT\_v4\_5.md` / `TRACK\_\[YOUR\_TRACK]\_v4\_5.md`) — but per the doc-discipline rules this project follows, treat even that as needing a fresh check against `SESSION\_HANDOFF.md` §1 rather than hardcoding trust in this correction either. Read items 1–2 above as `v\[CURRENT]` in spirit, always verified against `SESSION\_HANDOFF.md` §1 at session start, not assumed from any single file's own claim — including this one.

3. `docs/SESSION\_HANDOFF.md` — current repo-audit state; check this is
current before trusting it (see its own expiry note)
4. `docs/KOI\_TEAM\_AGENT\_WORKFLOW.md` — the process to follow for every task

## Hard, non-negotiable specifics (inline so you never have to guess)

* **Crypto:** AES-256-GCM, PBKDF2-HMAC-SHA256, 600,000 iterations, salt from
Firestore at `users/{uid}.public\_crypto\_metadata.salt` (NOT Firebase Auth
metadata). Payload format: `v1:PBKDF2:base64(salt):base64(nonce):base64(ciphertext\_with\_mac)`
* **Trust boundary:** This is Client-Side Encryption (CSE) at rest, NOT
E2EE. Never label it E2EE in code, comments, or UI copy.
* **Chat endpoint contract:** `POST /api/v1/chat` returns
`{ "response": { "reply": string, "companion\_state": { "emotion": string, "intensity": number }, "latency\_ms": number } }`.
5 strict emotion strings only: `neutral`, `joy`, `angry`, `sorrow`, `fun`.
`latency\_ms` = time-to-first-token under streaming, not full generation.
* **Avatar bridge:** `webview\_flutter` + `JavascriptChannel` named exactly
`KoiBridge`. Readiness: `window.KoiBridge.postMessage('AVATAR\_READY')`.
Emotion injection: `AvatarController.setEmotion(emotion, intensity)`.
WebView never makes its own network calls.

🆕 **\[v4.13 ADDITION — Sep 1, 2026] Missing inline specifics — this section's own stated purpose is "so you never have to guess," and these four items were locked in canon but never surfaced here. Added now, not previously an oversight this file called out itself.**

* **`companion\_state` field-ordering (CRITICAL, easy to get backwards silently):** in the structured JSON generation for `POST /api/v1/chat`, `companion\_state` must be generated **before** `reply` in the same call — not after. If `reply` generates first, the avatar can't know which expression to show until the whole reply has streamed, silently defeating token-level streaming for anything the avatar visually does. Full detail: Blueprint §4.1.
* **Streaming transport — implementation method locked:** SSE/WebSocket transport must use FastAPI's native streaming support (`StreamingResponse` or native `WebSocket`) or a vetted SSE helper library — never a hand-rolled chunk-framing/event-encoding protocol. Full detail: Blueprint §4.1 (v4.9 addition).
* **`POST /api/v1/crisis` (Multimodal TSD Evaluation) — MVP-required, not stretch (see Out-of-Scope correction below).** Returns `crisis\_score` (continuous, 0.0–1.0), `risk\_category`, `trigger\_flags` (array — any flag structurally dependent on a missing modality is **omitted entirely, never returned as `false`** — a false-style default is indistinguishable from "checked and clear," a false-negative risk in a crisis context), and `modalities\_used`. At `risk\_category` ≥ HIGH, the response also carries `intervention\_content` — a new field on this same response, populated only above HIGH, not a separate endpoint — grounded via RAG over a locked four-corpus set (AnnoMI, CBT-Bench, MentalChat16K, WHO/SAMHSA), with CRITICAL-tier retrieval restricted to non-synthetic sources only. Full detail: Blueprint §4.1, §8 item 7.
* **TSD invocation model — locked, not purely client-triggered:** the TSD forward pass runs as an **automatic background check on every conversational turn**, using whichever of the four locked modality combos is present that turn (including Text-only) — not only when a client explicitly submits to `/api/v1/crisis`. An explicit "check on me" client-invoked path may still exist as an additional option, but is not the sole invocation path. Full detail: Blueprint §4.1d.
* **Crisis media trust boundary — deliberate, not an oversight:** raw `.wav`/`.mp4` crisis uploads are protected by TLS-in-transit only, not wrapped in the AES-GCM CSE payload format (TSD encoders need raw features, not ciphertext). This is the system's most sensitive data category with its weakest documented protection — a stated trade-off, mitigated by deleting raw media from the server immediately post-inference, never persisting it. Full detail: Blueprint §3.1a.

## Process reminders for the agent itself

* Stop after implementing + testing a task and wait for explicit human
confirmation before starting the next one. Do not chain tasks silently.
* Write tests in the same pass as the implementation, matching existing
test file patterns already in this repo.
* If a task touches the crypto payload, the chat API schema, the emotion
enum, or the avatar bridge protocol, flag it explicitly — these need a
golden test vector validated against the other repo(s), not just local
tests.
* If anything in the docs contradicts what you find in the actual repo,
say so explicitly rather than silently reconciling it — this exact kind
of silent gap is what caused real problems earlier in this project (see
`SESSION\_HANDOFF.md` §3).

## Out of scope for now (do not implement unless explicitly asked)

* TSD Crisis Engine (Tier 2 Research / stretch goal — Master Phase 5)
* Anything not in your track doc's current, still-open Phase

🆕 **\[v4.5 ADDITION] Correction to the first bullet above:** "TSD Crisis Engine... stretch goal" is **no longer accurate** as of v4.5 — TSD (Master Phase 5) was promoted to MVP-required scope (see Blueprint §8 item 6, `SESSION\_HANDOFF.md` §12). The bullet is left unedited above for traceability but must not be followed literally. Current guidance: TSD work IS in scope once your track's Phases 1–3 (or equivalent) are defense-ready — check your track doc's Phase 4 section, now reframed as MVP-required, not stretch.

🆕 **\[v4.13 ADDITION — Sep 1, 2026] Current TSD status, for whichever agent is working the AI/Backend repo specifically.** Two things a coding agent on this track needs to know before touching TSD work: (1) **the crisis-training-data strategy changed** — synthetic mismatch-pairs (from IEMOCAP+MELD) remain primary, but the self-recorded Masking Dataset is now *always* incorporated as a supplementary real-data signal for the `crisis\_score` head, regardless of the synthetic PoC's own pass/fail result — this is a locked architecture decision, not a fallback contingency anymore; see Blueprint §8 item 8 (v4.13 addition), `KOI\_TSD\_POC\_PLAN\_v1.md` Phase 6 (v1.3 note). (2) **Phase 5 (A3 subspace-separation validation) has never been run** — no file records a completion or result, and it's confirmed as a real blocking task, gating Phase 6 and all downstream full-scale TSD training. If an agent is asked to work on TSD training and Phase 5 hasn't been done, that's the actual next step, not full-scale training. See `KOI\_TSD\_POC\_PLAN\_v1.md` Phase 5 (v1.4 note), `SESSION\_HANDOFF.md` §21.3.



\---

🆕 **\[v4.24 ADDITION — Oct 11, 2026] RAG segment — what an agent working the AI/Backend repo must know.** Nothing above was edited. Full state: `KOI\_RAG\_SEGMENT\_STATE\_v1.md`.

* **The four-corpus statement in the `POST /api/v1/crisis` bullet above is stale for the RAG prototype.** The built corpus is AnnoMI + WHO mhGAP + SAMHSA + mhGAP-HIG-PK (6,852 chunks); CBT-Bench and MentalChat16K are not built in. Blueprint v4.24 addition flags this contradiction. Do not "fix" either side; flag it.
* **`intervention\_content`'s internal shape is not specified in canon.** A DRAFT is in `KOI\_RAG\_SEGMENT\_STATE\_v1.md` §8 and is **unconfirmed**. Client tracks: render whatever the backend returns and do not hard-code fields from the draft until it is confirmed and propagated to the Web and Flutter track docs.
* **RAG runs only on the crisis path at `risk\_category` >= HIGH** (never after every chat turn). At CRITICAL the response is a deterministic fallback, never a retrieved span.
* **No external AI APIs** still applies to the RAG layer (embeddings are local `sentence-transformers`). If a framework is adopted for the RAG pipeline, disable its telemetry in the process that launches the service and verify with an offline egress test.
* **Windows dev machine:** use `python` (not `python3`); scripts must use `Path(\_\_file\_\_).resolve().parent.parent`-relative paths, never hardcoded `/home/claude`.
* Do not claim the RAG layer "improves" the crisis path in docs or UI copy: Blueprint §8 item 7 requires *demonstrated* improvement and the VERA-MH evaluation has not been run.

\---

🆕 **\[v4.27 ADDITION — Oct 12, 2026] RAG segment — stale-text notice for any coding agent on the AI/Backend repo.** Nothing above was edited or removed. Chat-generated; unverified until Ahmad confirms this file was swapped into the Project. Full state: `KOI\_RAG\_SEGMENT\_STATE\_v1.md` v4.27 addition (its §9 is the resume point). This supersedes, where they differ, the "v4.24 ADDITION — RAG segment" bullets directly above.

* **`intervention\_content` is no longer "unconfirmed".** Ahmad confirmed the `KOI\_RAG\_SEGMENT\_STATE\_v1.md` §8 contract and it was propagated to the Web and Flutter tracks as v4.25. Blueprint v4.24 item 7 and Backend v4.24 §6 still say DRAFT/PROPOSED (not edited). At most **3 items** per response. Open and unresolved: `risk\_category` enum strings (`HIGH\_CRISIS` vs `HIGH`/`CRITICAL`) and the helpline number (1166, unverified) — do not hard-code either.
* **The corpus/pool statements above are stale for the RAG design.** HIGH-tier retrieval pool is decided (under Ahmad's delegation, not separately reviewed) as the **22 guideline chunks** (26 minus four US-only 988 chunks); AnnoMI is out of user-facing HIGH responses. This contradicts Blueprint §8 item 7 v4.8 ("includes all four verified corpora"). Flag it; do not "fix" either side. Corpus is frozen after the defense.
* **Retrieval design decided \[DELEGATED]:** multilingual-e5-small embeddings (not MiniLM); BM25 only when the query contains Arabic script, dense otherwise (Unicode-word BM25 measurably hurts Roman Urdu / code-switched text); kNN routing over labelled example queries; a similarity gate whose threshold is dev-fitted (0.5709, rule G) — below it the response is the deterministic fallback (`source: "fallback"`), same as CRITICAL. **Not yet implemented in `retrieval\_pipeline.py`** (its default is still `bm25\_tokenizer="unicode"`). The one-shot holdout run is not built.
* **Do not claim** the RAG layer is validated or "improves" the crisis path in docs or UI copy: a fixed 3-chunk bundle reaches 92% Hit@3 vs 83–86% for kNN, the gate's false-accept figure is dev-fitted, labels are LLM-adjudicated (no human or clinician verification), and VERA-MH has not been run.
* Haystack is approved (plain-Python components wrapped as custom components) but not built; telemetry must be disabled in the launching process and verified by an offline egress test.

---
*
🆕 [v4.30 ADDITION — Oct 15, 2026] Exercise director (koi_policy) + RAG status — what an agent on the AI-Backend repo (koi-ai-engine) must know. Nothing above was edited or removed. Chat-generated (Ahmad Suleman + Claude); unverified until Ahmad confirms this block was saved. Label check: a Project search on Oct 15 found v4.29 as the highest label and no "v4.30"; a search is not a full grep, so Ahmad should confirm before saving.

A. Stale text above — read these corrections before acting on the v4.27 block

Each line quotes the stale side, then the newer source. Do not "fix" either side; flag it if it blocks you.

v4.27 says the gate is "a similarity gate". Stale: the gate is the top chunk's vote share >= 0.5709 (SESSION_HANDOFF.md §30).
v4.27 says the retrieval design is "Not yet implemented in retrieval_pipeline.py" and Haystack is "not built". Stale: the router is code and Haystack 3.3.0 wrapper is built and sandbox-tested; tests/egress audit on Ahmad's real machine were still pending as of §31 (SESSION_HANDOFF.md §30, §31).
v4.27 says "BM25 only when the query contains Arabic script". Superseded [LOCKED, Ahmad: "1 keep and disclose, 2 drop"]: no BM25 on the served crisis path (SESSION_HANDOFF.md §31; claude/KOI_RAG_ADR_001.md v4.29 note).
[LOCKED] zero-vote chunks are no longer served: items = chunks with votes > 0, at most 3; none -> fallback (same sources).
Four different chat contracts exist today; none is declared the winner. Do not "fix" one to match another; flag it. (a) Hard-specifics above and SESSION_HANDOFF.md §2: atomic { "response": { "reply", "companion_state", "latency_ms" } }. (b) This repo's app/api/routes.py: one atomic response, not streaming; its latency_ms is full-generation time, not TTFT (canon says TTFT under streaming). (c) Modal chat_app.py (standalone file, NOT in this repo): SSE events latency / delta / done. delta.text is a raw fragment of the model's JSON string; done carries full_text (the raw JSON) and total_generation_s, with no companion_state key. (d) Web client conversationService.ts: expects delta.text to be reply text and done.companion_state to exist. Read against (c) as pasted, the client would show raw JSON and never receive an emotion. Verify against the real files. Generation order is still companion_state BEFORE reply (Blueprint §4.1e). 5b. Emotion strings disagree. Hard-specifics above: 5 strict strings neutral, joy, angry, sorrow, fun. Web normalizeEmotion accepts only happy, sad, anxious, calm, neutral, so any backend value other than neutral degrades to neutral there. Do not change either side; flag it.
SESSION_HANDOFF.md §2 still says "hand-rolled PyTorch only / no Langchain". Superseded by the v4.6 correction (Blueprint §1 item 1). Zero external AI APIs still applies.
Still open, do not hard-code: risk_category enum strings (HIGH_CRISIS vs HIGH/CRITICAL; Blueprint's own example uses HIGH_CRISIS, its threshold note uses LOW/MODERATE/HIGH/CRITICAL); helpline 1166 is unverified; fallback wording is a draft; the 3-of-22 audience table awaits Ahmad's approval.
Deadline: v4.27 says committee 16 Oct; SESSION_HANDOFF.md §28 says defense 17 Oct. Unreconciled.
B. What koi_policy/ is (chat-built, Oct 14-15, 2026 — not in any canon file yet)

A server-side exercise director: breathing, grounding, task-planning (and a CBT hand-off stub) delivered inside normal chat, spoken by the avatar. Nothing is a form (UX Flow 10: "not a form"; Flow 5 is a conversational offer).

Pattern: deterministic director picks the step; fixed reviewed lines (journeys.json, en / ur / ur-roman) carry every instruction, number, timing and question; the companion LLM writes only a <=2-sentence, <=25-word acknowledgement; every LLM sentence is checked before release; on failure one retry, then a reviewed fallback line.
Modules: policy.py (when to offer), intents.py (reads replies, with abstention; distress override), compose.py (sentence gate, phrase_fn contract), state_token.py (HMAC-SHA256 signed client-carried state; secret from KOI_DIRECTOR_SECRET), director.py (handle_turn, on_risk), catalogue.py + exercises*.json.
Baseline tests (from koi_policy_20261015b.zip): test_director.py 71, test_policy.py 44, test_catalogue.py 34 checks. test_breathing_ui.py (56, needs Playwright) covers a retired standalone page kept only as an animation-timing reference. If your counts differ, report it; do not edit tests to match.
Inputs per turn: text, client_event, tier (None = risk check unavailable), score, flags, lang. Fail-closed: tier None -> no exercise starts.
Canon alignment chosen by Ahmad (chat, Oct 15): A keep Blueprint §4.1d / Gate 1b-concurrency (c): TSD stays an independent background check each turn and a HIGH/CRISIS result surfaces without being rewritten; plus a fast distress pre-check before the acknowledgement is generated, in exercise mode only. B exercise mode only: the acknowledgement is buffered and released per completed sentence (same unit as TTS, Blueprint §4.1e). B is NOT yet written into canon — do not claim canon permits it.
C. PROPOSED contract additions — NOT agreed with the Web or Flutter owners, NOT in Blueprint

Optional additions only, never rename or reorder existing ones: request exercise_state (opaque signed string); response exercise_state, ui_action (e.g. breathing: inhale 4 s, exhale 6 s, 6 cycles, "at your own pace"), handoff (companion | crisis | cbt_module). On an atomic route these are optional JSON fields; on an SSE route they would be extra events with the same names. Which transport carries them depends on the unresolved contract in section A item 5. Per this repo's own rule, any chat-schema change needs a golden example validated against the other repos — produce the golden example and stop; do not assume the clients accept it.

D. Hard rules for this task
Do NOT modify: director.py, policy.py, intents.py, compose.py, journeys.json, catalogue.py, state_token.py, any test's expectations, or any canon/docs/ file. If one of these blocks you, stop and report.
You MAY add: adapter_qwen.py (a phrase_fn(direction) -> (companion_state|None, token iterator), contract in compose.py docstring; companion model is Qwen/Qwen3-4B-Instruct-2507, self-hosted — no external AI API), the route wiring, and new tests.
Never put the signing secret in code; read KOI_DIRECTOR_SECRET; refuse to start without it.
No clinical claims anywhere. Fixed lines in all three languages are drafts with no clinician or native-speaker review; do not edit or "improve" them.
RAG: never run, tune or read the holdout (rule E is spent). Set HAYSTACK_TELEMETRY_ENABLED=False and HF_HUB_OFFLINE=1 in the launching process.
Windows dev machine: use python (not python3); paths via Path(__file__).resolve().parent, never hard-coded.
Flat imports (import compose as K) mean the folder only works when its directory is on sys.path. Do not relocate or convert to a package until tasks 1-3 pass; relocation is its own final task and may change import lines only.
Stop after each task and wait for Ahmad. Do not chain.
E. Task list (one at a time)
adapter_qwen.py + test against a fake streaming server.
Wire director.handle_turn into /api/v1/chat; existing chat tests unchanged and passing; companion_state before reply; golden JSON example (section C).
Wire director.on_risk to the existing per-turn TSD result; add an HTTP-level test that HIGH risk mid-exercise goes to crisis at every waiting step.
(Only after 1-3 are confirmed) relocate to app/services/exercise_director/ with relative imports; tests move with it; only import lines change.
F. Required report after EACH task — Ahmad pastes this back for verification. Missing items count as NOT DONE.
 1. Exact commands run and their raw output (not a summary).
 2. test_director.py / test_policy.py / test_catalogue.py pass counts (baseline 71 / 44 / 34).
 3. git diff --stat listing every changed file; confirm none of the protected files in D changed.
 4. Existing chat/API test results before and after the change.
 5. For the route: one real response JSON, showing the response wrapper and field order.
 6. Fail-closed proof: output of a test where the risk check is unavailable and no exercise starts.
 7. Tamper proof through HTTP: edited state token rejected; missing secret refuses to start.
 8. Adapter: raw output of 5 real acknowledgements each in en / ur / ur-roman, each labelled generated or fallback with the notes list; plus the fallback count out of 15.
 9. Latency: time to first released sentence (p50 / p95 over >= 30 turns), exercise vs normal turn, or an explicit "could not measure, because ...".
 10. Network: list of any new outbound calls; confirm only the model endpoint.
 11. grep showing no hard-coded secret and no /home/claude paths.
 12. Contradictions found between docs and repo, each quoting both sides.
 13. Anything skipped, guessed or not run, stated plainly.
