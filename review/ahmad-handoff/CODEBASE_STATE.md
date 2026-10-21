# KOI codebase state (2026-10-21) - read this first

For engineers and AI agents joining. Names only, no secrets. [UNVERIFIED] = reported but not independently checked.

## 1. What this is
KOI = (a) the companion (KOI 1.0): anonymous AI companion chat, avatar, voice, crisis detection; Next.js web, Flutter mobile, Modal backends (chat, crisis, speech), Firebase anonymous auth. (b) the care platform (KOI 2.0): General User, Patient, verified Psychologist roles; questionnaires; messaging; appointments; notifications; demo payment; analytics; AI-assisted questionnaire drafting and AI evaluation drafts. Product rules: patients NEVER see scores, AI interpretations or evaluation status (even after review); the AI never publishes, diagnoses or acts alone; all results are psychologist-only. All data is synthetic (university FYP).

## 2. Repos and branches
- Web: monorepo github.com/Koi-fyp/Koi. App dir: repos/koi-backend/nextjs_app (Next.js 14.2.35). Branch integrate/web-ahmad = the Web owner's handoff branch handoff/koi-web-1-to-5-2026-10-20 (commit ffc91f9) plus Ahmad's commits: .gitattributes (-text for pinned illustrations and contracts), live-rules test script, AI-assisted drafting (route + builder panel + confirm-review), Messages screen. Do not push to master.
- AI: github.com/Koi-fyp/KOI-Psycholov. master = tag ai-contracts-draft-0.4. Feature branch feat/koi2-ai-gen-web (includes feat/koi2-ai-web-wire): Web job adapter, worker modes, Web-shaped generate target. Python package koi2_ai/ (api, chains, validators, providers, adapters/web_platform, worker), contracts/, reports/, resources/psychology/, scripts/, tests/. CLAUDE.md = binding decisions for the AI side.
- Not in git: .local/ (reports, evidence, manifests), E:\Koi\private (credentials), E:\Koi\demo (copied into review/ahmad-handoff/demo-scripts).

## 3. Architecture in one page
- Platform backend = the Next app's /api/v1 routes (Firebase Admin SDK, Firestore transactions). Authority comes only from backend records: accounts, psychologist_verifications.state=='verified', organization owner + membership, patient_relationships active. Client Firestore access to platform collections is denied; never trust client roles or claims.
- Contracts: Web package v0.5.2 (wire literals 0.5.0), frozen; never edit a frozen version, add a new one.
- Companion is separate: default Firebase app (anonymous), NEXT_PUBLIC_KOI_API_BASE / NEXT_PUBLIC_KOI_SPEECH_BASE point to Modal. Care login is a separate named Firebase app (email/password). No account linking between them.
- AI boundary: Web owns ai_jobs/job_<hash(sid)> and clinician_evaluations/evaluation_<hash(sid)>, created in the patient submit transaction. The AI worker (koi2_ai.worker --store web) claims the job in place and fills the evaluation envelope (interpretation, evidence, validated_scores, provider_response_sha256); detail goes to AI-owned ai_* collections. The psychologist sees it in the submission review after clicking Refresh evaluation.
- AI drafting: builder panel -> POST /api/v1/professional/questionnaire-drafts/ai (Next, server-side, env KOI_AI_BASE) -> AI service POST /api/v1/ai/questionnaires/generate with target web_platform_0_5. Drafts arrive origin ai_drafted; publish requires origin manual; POST .../confirm-review flips it on the server after the psychologist confirms review.
- Provider: AgentRouter through the Anthropic SDK (sync client), single model deepseek-v4-flash, thinking disabled. MockProvider is the default and returns canned text.

## 4. Run it (Windows, conda prompts)
Envs: koi-web (Node 22 + Java 21; set npm_config_cache=E:\Koi\npm-cache) and koi2-ai (Python 3.11). Demo scripts in review/ahmad-handoff/demo-scripts: 1_emulators (Auth 5199, Firestore 5180), 2_server (Next dev on 3107, KOI_AI_BASE=http://127.0.0.1:8100), 3_seed (fictional accounts; asks for a 12+ char password), 5_ai_api (mock) or 5_ai_api_live (needs AGENTROUTER_API_KEY in that window), 4_worker (one pass, mock), 4b_worker_poll, 4c_worker_live, 6_live_server (cloud mode). Seeded logins: psychologist@ / general@ / patient@koi-demo.example. Cloud mode and the emulator demo both use port 3107: run one at a time. Live project koi-companion-fyp holds fictional accounts koi-exam-{psychologist,general,patient}-examiner_2026@example.invalid; its server needs fresh rules evidence (expires 24 h after the audit). Tests: Web npm test -- --runInBand (about 778); AI python -B -m pytest -p no:cacheprovider -q (about 694 passed, 6 skipped without emulators).

## 5. Status
Reported working by Ahmad in rehearsal: emulator demo, manual care flow, AI draft generation. Tested only with mocks: Messages screen (never rehearsed live), the confirm-review gate. Not working or unverified: see section 6.

## 6. Known errors and gaps (open)
1. Evaluation showed "Unavailable (invalid_output)" on the 2026-10-21 rehearsal. Cause not diagnosed: check the worker window and the ai_audit documents. A failed Web job is terminal (no re-run); a new submission makes a new job.
2. scripts/live_common.py counts a stale 401 row (2026-10-19) in reports/usage_ledger.jsonl and refuses live runs until SESSION_SINCE is moved after it. Do not edit the ledger.
3. Spark quota (shared with live KOI 1.0): capabilities polling (2 s stream + 5 s nav) is about 10,100 reads per tab-hour; Messages polling about 22,600 per tab-hour (agent estimates from code, not measured). The polling patch is NOT applied. Emulator is unaffected. Keep tabs few on the live project.
4. Messages: no realtime push, no read/seen ticks (contract has none), desktop notifications only while the tab is visible, 300-message view limit. Not rehearsed live.
5. AI drafting: images refused for the Web target, numeric unsupported; mock provider returns canned drafts unless the live AI API window is used. AgentRouter: one model, no fallback, terms of use for backend traffic unresolved, some Urdu input was content-blocked in earlier runs.
6. Evaluation UI: queued text is stale ("worker is not connected in this slice"); claimed/completed show raw; refresh is manual; no screen for comparisons or Evidence Guard detail; validated scores are empty because Web publishes manual custom forms only.
7. No self-registration in the UI; accounts come from seeder or provisioning scripts. Anonymous companion users cannot become care accounts.
8. Contracts: Web 0.5.2; AI 0.4 (tag). Unapplied proposals: AI wire (0.5), gen-web (0.5/0.6), Web AI-drafting and confirm-review routes (0.5.3). Web OpenAPI x-status values are stale. answer_index meaning (0-based position in submission.answers) is an unconfirmed default.
9. Data: Urdu text in frozen contracts fixtures and the illustrations manifest is literal question marks (encoding damage in the frozen file). Urdu WHO-5 transcription is unverified and disabled. No native-speaker review of Urdu/Roman Urdu claim patterns.
10. Windows checkouts convert LF to CRLF: fixed on integrate/web-ahmad (.gitattributes); the Web owner's branch fails service.test.ts on Windows.
11. /api/auth/anonymous is unauthenticated and not rate limited (writes users docs). No AI-specific consent record exists (care-consent-v1 stands in). The AI worker refuses the live project by design (emulator only).
12. UI/UX debt (known, not fixed): visual overhaul, decluttering, routing gaps, general usability polish.
13. A historical credential exposure exists in the monorepo history (owner-managed). Never read, print, commit or rewrite secrets.

## 7. Rules for anyone working here (human or agent)
- No secrets in git, logs or chat: names only. Never read .env files or credential files.
- No writes to the live Firebase project and no re-running provisioning without the owner.
- Never expose scores, AI output or job state to a patient.
- Do not edit frozen contracts; Evidence Guard and banned-claim lists (AI repo) change only with the owner's approval.
- Local commits on a branch, no force-push, no push to master. Run tests before committing. Verify claims against code; reports here may be wrong.

## 8. More detail
Web: review/final-handoff/*, review/web-5/*, contracts/v0.5.2/*, review/ahmad-handoff/local-reports/*. AI: CLAUDE.md, contracts/WEB_HANDOFF.md, reports/WIRE_REPORT.md, reports/GEN_WEB_RUNBOOK.md, reports/WEB_E2E_RUNBOOK.md, reports/DEMO_SCRIPT.md.
