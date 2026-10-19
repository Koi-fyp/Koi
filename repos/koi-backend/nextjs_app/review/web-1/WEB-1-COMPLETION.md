# WEB-1 completion — manual professional publishing

**Implemented and demonstrated locally on `feat/web-1-professional-publishing`.**
Base HEAD remains `1390f1b3da96270ad47d8edfa06510ed838add77`; no commit, push, merge,
reset, deployment or destructive Git operation was performed. Existing application
files are unchanged. All WEB-1 implementation files are additions; the accepted
WEB-0.5 packet and other owners' untracked work were preserved.

## Delivered behavior

- `/professional` is separate from the companion layout. It reuses Neo buttons,
  inputs/cards, typography, theme tokens, borders/shadows and spinner styling.
  Loading/error/denied/session states, responsive layouts and scoped reduced-motion
  support are included. Named professional Auth leaves the companion session alone.
- A restricted CLI records server-owned account registration and psychologist
  pending/verified/rejected/suspended transitions with administrator/service identity,
  evidence references, authority revisions, idempotency and append-only audit events.
  No self-verification UI or public approval endpoint exists.
- A verified registered psychologist creates one organization and owner membership
  transactionally. Every practice operation checks current account state, verification,
  stored organization ownership and active membership. Client profile fields, provider
  flags, names and submitted organization IDs never grant authority.
- Clinicians can create/save/reopen manual drafts with all seven agreed question
  types, EN/UR/Roman Urdu custom content, RTL Urdu and three bundled geometric picture
  choices. The server validates strict schemas, locale coverage, unique IDs, option
  cardinalities/bounds, asset ID/version/hash and content size. Custom forms remain
  explicitly **not validated**.
- Saves use optimistic revisions. Publishing checks the confirmed revision/content
  hash and creates one immutable version. Duplicate publication returns the same ID
  and timestamp. Later draft edits do not modify old snapshots. Versions can be
  reopened by bookmark or by published draft revision after refresh.
- Same-account recent-auth confirmation preserves unsaved edits before dispatching a
  privileged write. Invalid/revoked sessions or lost practice access clear protected UI.
  All new backend responses are private/no-store and schema-checked explicit DTOs.

Implementation coverage: [8 frozen operations](../../contracts/implementations/WEB-1.md).
No patient/evaluation/job route, anonymous migration, AI generation, instrument seed,
push service, payment or Flutter implementation was added. AI is disconnected;
manual authoring/publishing does not depend on AgentRouter or a substitute model.

## Exact files and contract discipline

See [changed-files.md](changed-files.md) for every added implementation, test,
operational, report and evidence file, and [changed-files.json](changed-files.json)
for hashes. Grouped entry points are:

| Area | Location |
| --- | --- |
| Server authorization, Firestore adapter, revision/idempotency/publish logic | `src/lib/platform/server/` |
| Shared WEB-1 types, canonical hashing, allowlist, isolated Auth/API client | `src/lib/platform/` |
| Professional pages, styling and loading route | `src/app/professional/` |
| Manual editor, read-only published preview and reauthentication | `src/components/professional/` |
| Actual Next API handlers | `src/app/api/v1/me/capabilities/` and `src/app/api/v1/professional/` |
| Restricted verification CLI / real emulator browser harness | `scripts/platform-verify-psychologist.cjs`, `scripts/web1-emulator-functional.cjs` |
| Original bundled vector assets | `public/illustrations/web1/` |
| Unit/authorization/contract/functional tests | `src/__tests__/platform/`, `test/platform-memory.ts` |
| Local emulators only / operational handoff | `dev/platform-emulator/`, `review/web-1/` |

**Wire contract deviations: none.** Frozen 0.5.0 files retain their original hashes.
Only the WEB-1 subset is implemented. Defensive operational limits are documented:
512,000-byte requests, 400,000-byte canonical content, bounded pagination and fresh
authentication. AI-origin/custom instrument workflows remain unavailable rather than
returning artificial success. The new illustration manifest conforms to the frozen
manifest schema; these are developer-reviewed original neutral shapes, not externally
approved clinical instruments. No shared schema was silently edited for Mobile/AI.

## Tests executed and results

| Check | Result |
| --- | --- |
| Full existing + new suite: `npm test -- --runInBand --silent` | **PASS: 73 suites, 626 tests** |
| Final focused WEB-1 suite after audit-scope metadata check | **PASS: 7 suites, 42 tests** |
| `node scripts/validate-web05-contract.cjs` | **PASS:** frozen hashes, schema/reference/operation checks, 13 valid + 14 rejected fixtures, patient DTO boundary traversal |
| `npm run build` | **PASS**, including TypeScript; Next 14.2.35, 21 prerender generation entries; build ID `JPSWRYXul1ou9Pl7ESEhg` |
| Real Auth/Firestore emulator + real Next server + headless Chrome functional run | **PASS: 18 checks**, no mocked application responses or auth/storage adapter |
| Source preservation, bundle-name checks and `git diff --check` | **PASS:** existing source hashes preserved; no tracked-file modifications; no protected server/evaluation names in professional page chunks |

Final failing checks: **none**. The initial route test found cross-realm JSON handling;
it was corrected and retested. The server validator also wraps instances to avoid
schema-utils' special top-level-array mode, with explicit rejection tests. The browser
harness uses installed Chrome because Playwright's downloaded Chromium was absent.

The full suite passed before the final internal audit/receipt organization metadata
addition; the final focused suite, emulator journey and production build were rerun
after that addition. No existing companion source was changed between those runs.

The focused tests cover guests/general/unverified/rejected/suspended identities,
account/membership revocation, stale auth, forged cross-practice IDs and cursors,
concurrent edits, idempotency replay/conflicts, immutable snapshots, every question
type, localization, approved asset hashes, invalid payloads, transport sanitization,
UID changes, unavailable configuration and same-account reauthentication.

## Demonstrated user journeys

Evidence: [functional-emulator.json](evidence/functional-emulator.json),
[desktop screenshot](evidence/published-desktop.png),
[mobile screenshot](evidence/published-mobile.png).

1. In **local `demo-koi-platform-web1` only**, the restricted CLI transitions an existing
   synthetic password identity pending -> verified. Actual Firebase Auth emulator
   password sign-in produces a token checked by the application backend.
2. That clinician creates an organization, authors a text + picture questionnaire,
   selects a bundled triangle, saves revision 1 and publishes it.
3. A recent-sign-in prompt uses real reauthentication and keeps unsaved edits. Saving
   revision 2 changes the draft; the original published snapshot remains identical.
4. After refresh, the clinician reopens the draft and inspects published revision 1.
   A separate page load opens its saved bookmark. The 390px viewport has no horizontal
   overflow; desktop/mobile screenshots were visually inspected.
5. Signed-out, genuine anonymous and General identities cannot create a practice.
   Another verified clinician cannot read/list/create/update/publish in that practice.
   Concurrent real Firestore saves produce one success and one conflict. Direct client
   Firestore reads are denied by the new emulator-only deny-all rules.
6. Duplicate publish still returns one version. Suspending the clinician denies their
   existing token's subsequent professional requests and removes the workspace view.

Recorded outcome: **one published version for the tested organization, zero AI jobs,
zero companion requests and zero browser page errors**. Temporary local server and
emulator processes were stopped after verification; no live project was modified.

## Mocked/emulated functionality and deployment blockers

| Item | Actual verification boundary |
| --- | --- |
| Jest identity/storage/network | Test doubles are used; production has no memory-store or mock-auth fallback |
| Browser functional run | Real SDKs/API handlers/Firestore transactions and Chrome; Firebase Auth/Firestore themselves are local official emulators |
| Recent-auth clock case | Only the browser's freshness hint was advanced; real reauthentication and server clocks/authorization stayed intact |
| Verification evidence | Fictional review references and operator/clinician accounts; no real person's credentials or professional approval was created |
| Production IAM/rules/hosting | **Not verified or deployed.** Prior WEB-0.5 blockers remain |

Do not enable production until the active web/backend build/project binding, published
Firestore release/rules source, App Check/IAM and backend hosting are verified. The
production gate requires an explicit mode, matching project credential, cursor secret
and operator-attested rules hash; that hash does not automatically prove live rules.
The draft-list composite index is supplied as a **review proposal only**, not deployed.

No missing Flutter source or AI provider blocks this local slice. Real-patient
retention/onboarding policy and public registration inbox delivery remain later-track
prerequisites, not implemented or mocked here. Schema validation uses Next's existing
bundled Draft-07 validator; keep these tests when upgrading that dependency.

Reproduction, environment names, CLI restrictions and remaining deployment details:
[SETUP.md](SETUP.md). No actual credentials are included in the report or example.
