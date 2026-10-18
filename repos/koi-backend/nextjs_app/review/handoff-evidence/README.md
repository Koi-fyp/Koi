# Handoff evidence - review only

No credentials, browser profiles, raw user records, plaintext backups, downloads or unredacted runtime logs are included here.

- `current-verification.json`: fresh local-branch Jest/TypeScript/build results from the final handoff. No combined Ahmad-branch validation claimed.
- `browser-evidence-summary.json`: allowlisted assertion names/results, HTTP statuses and counts from previously executed synthetic browser sessions. Raw identity fingerprints, message content, ciphertext, headers, keys and response bodies are omitted. Historical results were inspected, not rerun during handoff.
- `browser-harness/`: verbatim copies of 22 authored local browser test scripts, formerly under ignored `artifacts/`. `browser-harness-provenance.json` records original paths and hashes so test source is not lost.
- `security-scan-summary.json`: paths/categories only; no matched secret values. Inherited tracked environment credential-shaped content requires owner review before push. Absence of pattern matches does not prove absence of secrets.

The harnesses are not a new production feature or a safe instruction to run against a personal account. Review before use, run from the Next app directory in a fresh disposable synthetic browser context, and create/adjust the expected ignored artifact output directory. They depend on local Chrome/Playwright and some use development webpack/React internals. Fixture adapters and key/preference manipulation are explicitly synthetic test operations; they must never be used against a real user database. Some older harnesses retain obsolete disabled-control assertions. Ahmad should adapt only relevant cases to his integrated app.

No harness was executed or runtime feature enabled by copying these source files. Raw screenshots/logs/profiles/exports stay local and excluded from the proposed commit. The exact local-only ignored-file index is `artifacts/web-final-handoff/excluded-ignored-files.jsonl` at the repository root; it is not proposed for publication.
