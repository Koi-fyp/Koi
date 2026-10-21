# PROGRESS — WEB_UNDERSTANDING.md build (session 2026-10-20)

Start state: HEAD ffc91f9201de4c1b690a7824c7ddbfe060776a91, branch handoff/koi-web-1-to-5-2026-10-20, working tree clean. No prior PROGRESS.md (fresh start).

- 1 READ ORDER AND DOC SUMMARY — DONE — all named docs read (web-2..5 found under APP\review\, not REVIEW\); manifest blobs match `git ls-files -s`; contradictions listed.
- 2 ARCHITECTURE MAP — DONE — 17 pages, 44 route files / 47 handlers mapped to service methods, auth gates and collections; patient-boundary code and tests listed.
- 3 COLLECTIONS — DONE — 30+ collections with writer/reader file:line, transaction exceptions and 12 composite indexes (one likely unused).
- 4 VERIFY CLAIMS — DONE — (a)-(e) all VERIFIED; (d) caveat: companion chat backend is external (NEXT_PUBLIC_KOI_API_BASE).
- 5 SCRIPTS — DONE — 6 npm scripts and all scripts\ files classified; cloud writers = web5-provision*, platform-verify-psychologist (in cloud shell); paid ping = web05-deployment-evidence.py.
- 6 RUN — DONE — tsc PASS (exit 0); jest 86 suites / 688 tests, 687 pass, 1 fail (service.test.ts asset hash).
- 7 ENV — DONE — names by mode from source; .env*/.env.example/platform.env.example NOT READ.
- 8 LOCAL DEMO RUNBOOK — DONE — 3-terminal emulator runbook with real paths; Java + Firebase CLI (npx download) flagged; avoid /chat.
- 9 CLOUD RUNBOOK — DONE — 11 ordered steps with RO/WRITES, evidence, rollback, approvals; 6 departures from docs noted (evidence expiry kills server, rules test trusts operator, etc.).
- 10 PHONE ACCESS — DONE — loopback bind, emulator hard-coded to 127.0.0.1, HTTPS needed (randomUUID/subtle), no CORS; mobile routes + contract 0.5.2 (wire 0.5.0).
- 11 AI BOUNDARY — DONE — ai_jobs created only at submit, never updated; Web calls no AI route; no AI consent storage; clinician_evaluations empty envelope.
- 12 FAILING TEST — DONE — same single failure; index LF vs worktree CRLF, no .gitattributes; CRLF-on-checkout is the leading explanation (hash check of LF blob NEEDS-APPROVAL: needs a pipe).
- 13 UNKNOWNS — DONE — 12 owner decisions, 11 questions for the Web owner.
- 0 EXECUTIVE SUMMARY — DONE — written last, placed at top of WEB_UNDERSTANDING.md.

Final `git status --short`: empty output. No tracked-file changes; no untracked files shown (.local/ahmad/ is ignored).
NEEDS-APPROVAL (not attempted): `git show HEAD:repos/koi-backend/nextjs_app/public/illustrations/web1/circle-v1.svg | <sha256 tool>` to confirm the LF blob hashes to cc6048…; any `firebase` CLI command.
BLOCKED-BY-PERMISSION: none.

ALL-DONE
