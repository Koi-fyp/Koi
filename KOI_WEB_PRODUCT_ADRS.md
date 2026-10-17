# KOI Web decision records — 2026-10-18

## ADR-HISTORY — session selection (DECISION NEEDED, joint P0 owner)

Verified: `db.conversations` has primary key `uid`; PersistentConversation loads/checkpoints one header via `get(uid)`. It does not expose switching or creation of a second persisted header. Owned message rows can retain multiple conversation IDs; they do not by themselves preserve each conversation's complete signed exercise/safety/session recovery state. Do not synthesize that state or replace the active session behind its adapter.

Proposed minimal interface, not deployed:

```ts
interface ConversationSelectorV1 {
  getSelection(): { ownerUid: string; conversationId: string; pending: boolean };
  openOwned(id: string, options: { signal: AbortSignal }): Promise<void>;
  createOwned(options: { signal: AbortSignal }): Promise<{ conversationId: string }>;
}
```

Joint owner must choose stable multi-conversation header authority/schema and behavior while pending. Recommended: navigation/list/search never cancels active SSE; explicit switching while pending returns busy rather than implicit cancel. Flush encrypted checkpoint atomically before selection; keep per-conversation safety/exercise state intact, reject unknown/foreign ID and stale owner/generation. Return readable locked/corrupt state without POST/replay. Tests: two sessions, reopen/refresh, pending-route navigation, duplicate prevention, failure rollback, UID switch, signed-state preservation. Until approved: read-only history/search and read-only transcript; Continue link only for the already active ID.

Additional required read-only crypto boundary: existing `getActiveCryptoContext` can generate missing anonymous secrets/salts and enqueue sync. A History read must never recreate keys when storage is missing. Proposed `withOwnedDecryptor<T>(uid: string, signal: AbortSignal, read: (decryptOwned: (ciphertext: string) => Promise<string>) => Promise<T>): Promise<OwnedReadResult<T>>`, joint security-owned; verify current identity on entry/each decrypt/exit, use only already available key, throw locked rather than generating/storing keys/salts or returning raw secret. Until reviewed, the app uses the already unlocked P0 session transcript for its current ID and labels other retained groups locked; the standalone query tests exercise injected decryptors. This is an explicit missing prerequisite, not an alternative key store.

**User review response 2026-10-18:** design review approved; implementation of decryptor/shared selector is **NOT approved**. Joint approval dependency: user + Ahmad. No protected architecture patch may be applied independently.

Proposed explicit result, for joint review rather than silently unlocking:

```ts
type OwnedReadResult<T> =
  | { status: 'ready'; value: T }
  | { status: 'locked'; reason: 'key-unavailable' | 'owner-unverified' | 'decrypt-failed' }
  | { status: 'unavailable'; reason: 'aborted' | 'storage-unavailable' };
function withOwnedDecryptor<T>(
  uid: string, signal: AbortSignal,
  read: (decryptOwned: (ciphertext: string) => Promise<string>) => Promise<T>
): Promise<OwnedReadResult<T>>;
```

Data flow: existing Firebase identity → verify owner/generation → read existing authorized in-memory/device key without creation → bounded owner-filtered storage query → scoped decryption callback → owner/generation check → ephemeral UI. No raw key returned, plaintext storage/cache, mutation, legacy adoption, network/sync, migration or recovery side effect. Authenticate record ownership as well as ciphertext decryption; successful decryption alone does not authorize adoption.

Potential affected files (proposal only): crypto owner adds one read-only capability to `src/lib/crypto.ts` or an approved security-owned facade; P0 owner adds selector to `PersistentConversation`/`ConversationContext` only after persistence ADR; `db.ts` changes only if jointly reviewed versioned header design requires them; Web then consumes adapter in history route/query. Current Web edits affect none of these protected files. Existing one-header-per-UID design cannot safely become multi-session merely by changing a React state variable.

| Regression case | Expected review/acceptance requirement |
| --- | --- |
| Missing/cleared anonymous or returning linked key | Explicit locked; **zero key/salt writes**, no cloud attempt; do not call creating lookup as fallback. |
| Legacy/ownerless rows and old signed state | Locked/read-only; no adoption, migration, delete, overwrite or fabricated safety/exercise state. |
| Correct owner/key vs foreign owner/key | Correct owner may read verified rows; foreign owner fails before exposure even if device key happens to decrypt. |
| UID switch/abort during storage/decryption | Ignore late plaintext, clear UI, no returned capability/secret persists. |
| Corrupt ciphertext/storage denied | Explicit decrypt-failed or storage-unavailable; no partially committed mutation. |
| Two conversations + refresh | Stable separate IDs, headers/revisions and encrypted recovery; reopening cannot reset another conversation's signed state. |
| Navigation while SSE pending | Existing request continues; no duplicate POST/user/reply; switching policy explicitly reviewed (busy suggested). |
| Failed explicit selection | Retain old active session and content, release proposed generation, no half-switched persistence. |
| Independent tabs | Revision conflicts fail closed; never overwrite newer header or silently adopt a different selected ID. |

Standalone read/query/UI tests are preparation; they do not approve this interface. Continue independent work while review is pending.

## ADR-PORTABILITY — supported key/identity context (DECISION NEEDED, security owner)

Same UID is not a decryption capability. Anonymous secret is browser-local; linked-secret recollection is not implemented. No key export, anonymous-account recovery, cross-owner transfer, password/rekey workflow, cloud deletion or db schema change approved.

Candidate initial capability: encrypted local backup readable only with the exact current owner/key context. Existing `encrypt`/`decrypt` primitive remains unchanged. A versioned authenticated manifest binds owner, source IDs/types, record counts/timestamps and ciphertext data. Outer checksum detects corruption only; authenticated encryption must authenticate metadata, not merely plaintext SHA-256. Never export Firebase tokens, raw keys, salts-as-secrets claims, traces, media or preview metrics. User-readable export is separate and requires affirmative sensitive-data consent.

Before enabling import: strict byte/record/schema limits, duplicate IDs/conflicts, verified decryption/owner/manifest and dry-run; confirmation bound to same owner/source revision; one approved transaction/staging write with rollback, active session protection, no sync/award side effects; duplicate import idempotence. Unsupported/older/tampered/zero/oversized files reject without writes. No import writer or UI enablement until joint approval and real supported-context round-trip/browser proof.

### Product-owner scope approval — joint security approval still pending

Approved target: encrypted **same Firebase owner UID + same existing authorized key**, no key creation/replacement/recovery/rekey/export, cross-owner transfer or legacy adoption. UID equality is not a key capability. Anonymous identity/key loss and returning linked-key collection remain explicit limitations; no browser-reset/cross-device promise.

Prepared types/parser: `src/lib/data-portability/backupDraft.ts`; proposed manifest `koi-backup-draft`/schemaVersion 1 includes exact ownerUid, nonsecret ownerBinding, createdAt, explicit same-owner-existing-key-only compatibility, supported source/counts and encrypted records. Unknown fields (including credential fields), malformed dates/ciphertext, duplicate source+ID, owner/count/schema/size/type mismatch reject. Body encryption uses existing CSE format; parsed structure is **not authenticated manifest integrity**. Parser returns `importAllowed:false`, integrity/decryption NOT VERIFIED. It does not declare a backup restorable.

Existing-key check/interface depends on ADR-HISTORY's joint-reviewed nonmutating decryptor. Read-only validation may test supplied decryptors, but production must not call key-generating lookup or export raw keys. A missing key produces locked. No import transaction is implemented. Proposed transaction after approval: recheck owner + source revisions + preview digest, validate/decrypt every record before transaction, reject any conflict (no overwrite), stable source+ID duplicate no-op, atomic approved tables-only insert/stage, abort rolls back all inserts; no automatic cloud push or reward issuance. Active header/safety state cannot be replaced through import. Exact tables and crash recovery must be signed off by Ahmad/user before writer exists.

Threat/test matrix: malformed/zero/oversized/outdated JSON, unknown fields/prototype keys, foreign UID, wrong/missing key, GCM tamper, count/metadata tamper, duplicate/re-encrypted conflict, stale preview, UID switch during read/decrypt/commit, cross-tab revision, interrupted write rollback and idempotent repeat. SHA/checksum is corruption detection only, not owner authorization or metadata authentication. Real restore and encrypted export download remain blocked until verified data access and format/authentication review; parser/dry-run tests are not a production round-trip.

## ADR-REWARDS — conflicting source rules (DECISION NEEDED, both product owners)

Primary inspected source: `C:\Users\PMYLS\Downloads\Koi-(SRS)v2updated.docx`, `word/document.xml`, paragraph indices count all `w:p` nodes from 1 (including table paragraphs).

Paragraph 482, exact quote:
> JPV-2: Add pieces for completed check-ins, activities, and milestones (2 pieces per conversation, 1 per check-in, 1 per breathing session).

Paragraph 496, exact quote:
> SRG-7: Award jigsaw piece if session completion is 80% or greater.

Same text/locations also found in `Koi-(SRS)v2updated (1).docx` and `(2).docx`; older `Koi-(SRS)v2 (2).docx` at paragraphs 430/444. Another local revised document contains JPV-2 without numeric awards; documents differ. These quotes are not current policy sign-off.

Conflict/questions: what is a conversation/session completion? Does 80% apply only to breathing or all activities? Are interrupted/repeated sessions eligible? What is a stable completion ID and source of truth? Existing exchange count is not therapy completion. How do 25 puzzle slots relate to milestone thresholds beyond 25 pieces? What happens to imported/legacy recorded balances?

Candidate only: voluntary completed check-ins/exercises, stable per-UID completion IDs and policy version, optional capped conversation award if approved; no rewards for risk/sadness/crisis, no punishment for inactivity, no inferred improvement. Require explicit rates, eligibility, caps/day/timezone, replay rules, milestone mapping and legacy reconciliation decision. No writer/award enabled before approval.

### Product-owner response — PROPOSED — AWAITING JOINT APPROVAL

User approves this proposal **subject to Ahmad's technical/security review and both owners' approval of provenance**; issuance remains off. This explicitly revises JPV-2's 2-per-conversation rate to 1, and clarifies SRG-7 rather than bypassing it.

| Source | Proposed amount / eligibility | Cap |
| --- | --- | --- |
| conversation | 1 piece, explicit persisted completion event plus at least one successfully persisted user–assistant exchange | 1/source/day |
| check_in | 1 piece, voluntary successfully persisted check-in with unique source ID | 1/source/day |
| breathing | 1 piece, measured ≥80% actual guided completion; six-cycle session requires at least five completed cycles | 1/source/day |

Every qualifying completion: authenticated owner UID, immutable completion_id, source_type, source record/session ID, actual completedAt, reward policy version. Dedup key `(owner_uid, source_type, completion_id)`; caps by **Asia/Karachi** calendar day. No SSE index, mutable message count or rotating signed exercise token as identity. Atomic owner-scoped recoverable writes and cross-tab idempotence require approved storage authority.

No awards for volume, greetings, failure/cancellation, crisis/handoff, opening exercise or notification preference. Back/End is not conversation completion. playback_done without measured provenance is insufficient. No emotion/risk incentives, clinical improvement claim, penalties, lost pieces or guilt/streak messaging.

One board, **25 slots**, fill next unfilled slot; permanent/idempotent unlocks at **5/10/15/20/25**. No board reset/additional board without policy review. Sample names are not achievements. Preserve legacy jigsawProgress exactly, no retroactive issuance or exchange-to-reward conversion; legacy reconciliation needs separate review. Board UI may render supplied saved-state records, not produce them.

Requested Ahmad tests: repeated delivery/reload/retry/account switch/cross-tab/import yield zero duplicate issuance; caps per source/Karachi midnight; five vs four completed cycles; failed/cancelled/crisis/Back/End cannot award; atomic completion/reward/slot receipt rollback; >25 behavior must not silently create/reset board; preserve legacy totals; independently verify completion provenance before enabling writes.

## ADR-ACTIVITY-STORAGE — encrypted user-entered ratings (DECISION NEEDED)

Existing moodEntries fields are numeric plaintext schema; schema presence is not permission to write sensitive plaintext. New completion/check-in payload needs approved owner-bound ciphertext representation, key context, event identity and authority before persistence. Reuse protected crypto; no second database/localStorage JSON cache or hand-written crypto. Independent validation/forms/reducers may be tested without storing data. No clinical claims or mood inference from chat.

## ADR-MEDIA — existing services and shipping gate (BLOCKED on Ahmad evidence)

No live accepted input codecs/limits, voice-language pairing/output audio+cues, expiry/auth/cancellation or G0b report supplied in this checkout. Existing sandbox MicrophoneCapture/SpeechPlayback will be reused behind a typed adapter, not replaced. Direct audio submits once before transcript; review-first requires independent ASR-only capability. Urdu script/approved English pairs first; Roman Urdu/code-mixing text remains unchanged and text-only by default. Video remains planned after voice/input/privacy acceptance. No shipping permissions, controls or new endpoints enabled by this ADR.

Portability draft public binding definition: lowercase hexadecimal SHA-256 of UTF-8 `koi-owner:v1:` concatenated with the exact UID. This only detects inconsistent owner metadata; anyone knowing the UID can reproduce it. It is not a signature, secret, identity proof or authorization.
