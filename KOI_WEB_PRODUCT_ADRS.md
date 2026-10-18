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

## 2026-10-18 approved UX update (b384ce2 baseline)

UX-CHAT-01 is PRODUCT APPROVED: visible New Chat; automatically preserve encrypted previous history and create a new stable conversation ID; selectable securely decryptable history. Search is secondary. New Chat never completes or rewards a conversation. IMPLEMENTATION BLOCKED at protected session persistence/selector until joint Ahmad + product-owner technical approval. Current UI exposes the action disabled with truthful explanation; existing current-session continuation remains available.

UX-AVATAR-02 is PRODUCT APPROVED: Aisha/Raza may change during a conversation without changing ID, context, transcript or history. Reuse the existing UID preference resolver/writer and Settings AvatarPicker from both conversation routes. No session cancellation or new request is part of selection. Fox is retained unless explicitly changed. Voice pairing remains a future Ahmad-owned interface, not enabled media.

UX-REWARDS-03 is PRODUCT APPROVED; issuance/provenance remains AWAITING JOINT TECHNICAL APPROVAL. Explicit Complete Conversation is distinct from Back, End and New Chat. Check-in eligibility requires successful durable user-initiated save; breathing requires measured >=80% (five of six cycles). Existing rates, Karachi daily caps, immutable IDs, no crisis/retroactive/duplicate issuance, fixed 25 slots and thresholds 5/10/15/20/25 remain unchanged. UI explains explicit completion; saving and awards remain disabled. No new ledger/schema or reward writer is introduced.

### Minimal joint interface revision (proposal, not deployed)

```ts
interface OwnedSessionActionsV1 {
  // Serialize checkpoint + selection: failure retains previous active identity.
  createOwned(input: { ownerUid: string; expectedConversationId: string;
    signal: AbortSignal }): Promise<{ conversationId: string; previousCheckpointed: true }>;
  openOwned(input: { ownerUid: string; expectedConversationId: string;
    targetConversationId: string; signal: AbortSignal }): Promise<{ conversationId: string }>;
}
interface VerifiedCompletionV1 {
  ownerUid: string; completionId: string;
  source: 'conversation' | 'check_in' | 'breathing'; sourceId: string;
  completedAt: string; policyVersion: string;
}
interface ConversationCompletionAdapterV1 {
  completeExplicitly(input: { ownerUid: string; conversationId: string;
    expectedRevision: number; signal: AbortSignal }): Promise<VerifiedCompletionV1>;
}
```

Session adapter producer: joint P0 owner; consumer: Web conversation/history actions. Must use existing authorized key material only, validate authenticated owner, checkpoint before switching, preserve completed messages, serialize cross-tab races and fail locked/unavailable without migration. Define active-SSE policy explicitly before enablement: initial proposal reject switch while pending rather than cancel or duplicate POST. Avatar switching is independent and must remain allowed during streaming. Refresh must restore selected identity. Legacy histories stay locked/read-only without approved ownership/decryption. A rejection never silently creates keys or abandons the original session.

Completion adapter producer: approved durable activity owner; consumer: explicit Web confirmation/eligibility read model. A real persisted exchange and successful immutable completion receipt are prerequisites; arbitrary frontend counts/playback_done are not evidence. Persist completion independently from reward eligibility, with atomic/idempotent reward issuance only after joint provenance/storage review. Verified automatic check-in/breathing producers must supply durable source identity and measured evidence through the same reviewed authority; do not synthesize completion events from navigation or preferences.

Joint review test matrix: two conversations; refresh selected ID; pending SSE reject/safe retry with one POST; failed checkpoint retains current session; duplicate request IDs; UID change mid-await; locked/corrupt legacy rows; no missing-key creation; explicit completion once; New Chat zero completion calls; Karachi caps per source; 4/6 rejects and 5/6 accepts; retries/import/cross-tab do not duplicate pieces; no crisis/cancelled/failed rewards; all legacy counters unchanged. Affected protected files remain ConversationContext, PersistentConversation, ConversationSession, db and crypto (review only). Web-owned consumer: ConversationProductControls; existing history UI remains read-only until selector approval.

## Increment 03 � 2026-10-18 product UAT reconciliation and joint interface requests

Latest owner UAT supersedes old assumptions: both VRMs render for the owner and completed P0 text survives navigation/refresh. Those observations are owner UAT, not this agent's live Modal receipt. Current worktree is b384ce2 on feat/web-product-data plus preserved Increment 02 edits; Increment 03 does not replace them. Actual New Chat, older-session unlock, completion records, saved encrypted check-ins, rewards and backup restoration remain unimplemented/gated, not accepted merely because a disabled control exists.

### HISTORY joint implementation patch requested (no protected edits applied)

Existing db.conversations uses UID as primary key and status only 'active'; PersistentConversation.initialize loads get(uid), while checkpoint validates the same conversationId/revision before put. Creating a second ID through direct UI writes would invalidate recovery authority. Existing crypto context lookup can create material; it is not an authorized read-only unlock interface. Request minimal reviewed changes in src/lib/db.ts, src/lib/crypto.ts, PersistentConversation/ConversationSession, ConversationContext only after joint approval. No parallel Web session store.

Retain previous OwnedSessionActionsV1 and withOwnedDecryptor signatures. Exact transition proposal:

| State/action | Expected result |
| --- | --- |
| current idle -> New Chat | Serialize encrypted checkpoint; create distinct owned ID; durably select it; return receipt only after commit. Never emit completion or award. |
| streaming -> New Chat/resume | Return typed busy; retain active request ID/session/key; UI disables action with explanation. Ordinary route navigation preserves streaming. |
| idle -> resume decryptable historical ID | Verify owner + existing key; load selected snapshot; restore reviewed safety/exercise/session context; update durable selection atomically. |
| locked/ownerless/corrupt historical ID | Locked/read-only status; no key creation, adoption, overwrite or delete. |
| checkpoint/storage failure, stale revision, abort or UID switch | No new active ID; discard late plaintext; old transcript remains intact; return unavailable/conflict/owner-changed. |
| reload / second tab | Read actual durable selected ID and reject stale concurrent selection; no duplicate POST or saved assistant turn. |

Review whether current header/index needs additive schema migration plus active-selection record; Web proposes no migration independently. Return typed failures `busy | locked | owner-changed | conflict | storage-unavailable` without SDK/private payloads. Tests: A/B distinct IDs; A resume context; reload selection; UID and cross-tab race; checkpoint rollback; missing key no writes; legacy untouched; exactly one request during route changes.

### Completion/check-in/reward authority � product approved, issuance BLOCKED

`src/lib/activities/rewardPreview.ts` is **advisory calculation only**, not authority or storage. Every result sets issuanceAllowed:false. Inputs are untrusted until a joint durable producer attests them. It tests explicit persisted exchange, prospective policy provenance, consented saved check-in, measured >=80% cycles, crisis/cancel exclusions, owner/source/immutable-ID replay, Karachi completion-day caps and a full 25-slot board. Legacy jigsawProgress is never consumed as reward provenance. No source events, rewards, milestones or clinical scores are written.

Proposed joint producer types (not deployed APIs):

```ts
interface CheckInWriterV1 {
  getCapabilities(ownerUid: string): Promise<
    {status:'ready'; scale:{version:string; min:number; max:number; step:number}} |
    {status:'locked'|'unavailable'}>;
  saveConsented(input:{ownerUid:string; entryId:string; consent:true;
    occurredAt:string; scaleVersion:string;
    ratings:{mood:number;connection:number;energy:number}},
    options:{signal:AbortSignal}):Promise<{entryId:string; persisted:true; completionId:string}>;
}
interface VerifiedActivityReceiptV1 {
  version:1; ownerUid:string; completionId:string;
  source:'conversation'|'check_in'|'breathing'; sourceId:string;
  completedAt:string; policyVersion:string;
  provenanceRef:string; // Joint producer verifies persisted exchange/consent/measured cycles.
}
```

Producer owns existing-key encryption, approved schema, authenticated UID, exact validation and commit. Consumer may clear unsaved drafts on UID switch; plaintext drafts never enter localStorage/logs. No writer => ratings disabled and Save unavailable, not simulated success. Breathing provenance must refer to immutable guided session identity and measured completed cycles (five of six), not playback_done or a signed token as completion ID. Explicit conversation completion cannot rely on Back/End, cached exchange totals or failed/pending/crisis interruptions. Preserve separate completed_exchanges, completed_conversations and earned_pieces read models.

Reward ledger needs joint append-only encrypted authority and atomic completion/event/dedup/daily-cap/next-slot receipt, including cross-tab/import retry handling and immutable milestone receipts at 5/10/15/20/25. Completion is not the reward: cap/board-full must not falsify whether a real completion was saved. No retroactive historical issuance, legacy total conversion, board reset or new boards. Caller booleans are not verification; reducer preview cannot mint anything. Joint owners must decide policy activation boundary and verified eligibility source before issuing.

### Portability � exact draft vs restorable artifact boundary

Current accepted parser is **draft structural preview v1**, not a restorable backup format. Its records have only source/id/timestamp/ciphertext; they do not carry all message relationship fields, session ownership metadata or supported profile preferences needed for faithful restoration. No preferences/check-ins/rewards/raw media are supported by this parser. Do not rename it a complete backup or enable PDF/download/restore.

Request joint `readOwnedBackupSnapshot(ownerUid,{signal})` consistent read capability plus nonmutating `withOwnedDecryptor`; return only approved owned metadata/ciphertext and a revision receipt. Define strict record unions with actual conversationId, sender, replyTo and valid timestamps and permitted preferences; no keys/tokens/raw media. Authenticate the **whole** manifest and ownership/metadata, not a public owner SHA or file extension. Existing-key access must not generate or replace material. UID equality alone is insufficient; anonymous key/identity loss has no promised recovery.

Joint restore proposal: bounded file -> schema/owner/authenticated-decrypt/payload validation -> dry-run duplicate/conflict/revision receipt -> explicit confirmation -> recheck current UID/key/revision/no active SSE -> one approved Dexie transaction (all required tables), no overwrites/foreign adoption/partial writes -> durable receipt -> recompute read models without issuing historical rewards. Queue/cloud interactions, rollback on interruption and duplicate identical stable IDs need explicit review. Conflicting IDs block, no smart merge. Fresh-browser same-existing-key round-trip is required before download/restoration acceptance; not run without capability. No security-sensitive migration is implemented here.

### Media history and ownership clarification

Approved future persistence is authorized user ASR transcript + assistant text, encrypted in the same owner-bound conversation. Never persist/import/export microphone blobs, generated speech audio, camera video, frames or biometric features. Current message schema has no verified modality field; do not invent text/voice/video_assisted badges from guesses. A future reviewed schema may add provenance/modality without rewriting existing text. Roman Urdu display text remains unchanged; TTS off until evaluated. Text mode silent. VoiceOutput and AudioCaptureResult proposals remain Ahmad-owned deployment gates, with companion/owner/generation binding, HIGH/urgent cancellation and nonfatal TTS fallback. No shipping media enabled.

## History / Export manual UAT follow-up � 2026-10-18 (latest)

Owner UAT confirms current encrypted conversation is readable in History: 12 retained/readable messages and Continue Current Conversation. This is owner-observed evidence; no private transcript was inspected/copied by this audit. New Chat, independent A/B sessions and real backup restoration remain incomplete.

### Ciphertext export approval boundary clarified

The earlier blanket export blocker was too broad: copying existing owner-tagged ciphertext needs no decryption secret. `src/lib/data-portability/ciphertextExport.ts` now independently reads the existing messages/conversations tables in one read-only Dexie transaction. It calls no crypto context, key creation, checkpoint, sync, decrypt, encrypt or mutation. Request UID must match the actual Firebase identity before/after the asynchronous read; UI repeats the identity check before creating the downloadable Blob. Preparation requires affirmative metadata/key-limit consent. Account switch aborts/discards late results and hides the previous prepared export.

This is an **encrypted data copy**, not a verified/restorable backup. Per-record ownerUid/UID is an ownership marker selected under the current authenticated client, not a cryptographic ownership proof. Copying a format-valid payload does not authenticate it. Database transaction consistency means one committed local database view; message service and checkpoint writes occur in separate transactions, so it does not prove every current in-memory turn is durably reconciled. No cloud completeness or account-sync receipt is claimed. Preparing during a pending reply is refused by the UI; ordinary conversation/navigation behavior is not changed.

Format: `kind:koi-ciphertext-data-export`, `formatVersion:1`; scope owner-tagged-device-local-records; single-readonly-database-transaction; restorationSupported=false, decryptionVerified=false, manifestAuthenticated=false, originalKeyRequiredToDecrypt=true. Exact output allowlists ownerUid, exportedAt, counts, message id/conversationId/sender/timestamp/optional replyTo/ciphertext, available current snapshot owner/conversationId/createdAt/lastActiveAt/revision/ciphertext. Limits: 200 total messages+snapshots, 2 MiB UTF-8 JSON, each ciphertext <=100,000 chars and existing v1/PBKDF2 Base64 structure. Unsupported owned records fail rather than truncate. Foreign/ownerless records are excluded, not adopted; no plaintext risk/emotion fields, user profile/preferences, mood/reward rows, credentials/key material or raw-media fields copied. No schema changes. The file is intentionally NOT the existing koi-backup-draft preview format and cannot be restored through Import.

Export does not need the original key. Reading/authenticating the ciphertext later DOES require the correct original secret/key context for each record. Salt/nonce embedded in ciphertext are public, not a key. Anonymous secret loss or linked-session secret unavailability is not repaired by the file; same Firebase UID is insufficient. Different key generations cannot be reconciled by this exporter. No key availability is probed, generated or promised. The existing ConversationProvider blocks authenticated route children if the current session cannot unlock; therefore key-free reader tests do not prove the Export page is reachable in a locked account. A locked-mode route shell, if desired, needs joint review separately.

Restorable backup still needs nonmutating existing-key capability, authenticated complete manifest/relationship metadata, precise legacy/rekey provenance rules and approved transactional restore/rollback with same-context round-trip. None implemented. Wellness Report now has no generator, invented analytics, simulated progress or success template: empty data/source state only, separate from data export.

### ADR-HISTORY: smallest proposed shared patch for technical approval

No new decorative New Chat control was added. `src/lib/history/sessionTransition.ts` is a tested **consumer scaffold only**, not a session store or production adapter. It refuses pending replies, missing adapter, invalid/foreign/cancelled receipts and failed transitions. Fixture A->B->A tests are NOT real multi-chat or persistence acceptance.

```ts
interface ApprovedSessionTransitionAdapter {
  transition(input: (
    {kind:'new'} | {kind:'resume';conversationId:string}
  ) & {ownerUid:string;expectedConversationId:string;signal:AbortSignal})
    : Promise<{
      ownerUid:string;previousConversationId:string;
      conversationId:string;previousCheckpointed:true
    }>;
}
```

Minimal joint-review candidate is **two protected files** plus Web-owned consumers/tests:

1. `src/lib/db.ts`: review an additive version/table for archived owned session snapshots, e.g. `[ownerUid+conversationId]` primary key with owner index. Keep existing conversations UID primary key as the active pointer/recovery header. Do not replace/rewrite it, migrate ownerless legacy messages or convert existing jigsaw records. This additive schema is a proposal requiring approval, not an applied migration.
2. `src/lib/conversation/PersistentConversation.ts`: implement the atomic transition using its already authorized private secret/salt and existing encrypt/decrypt primitives. No change to crypto.ts algorithms/context lookup or Firebase authentication is needed for this candidate. Serialize transitions with pending checkpoint writes; lock against new sends; refuse pending SSE. Checkpoint current, validate target owner/decryption before changing selection, then atomically archive the legitimate prior header and select a new unique UUID or verified saved target. Publish new session only after commit; errors retain old identity/context. Never enqueue completion/awards. Archive stores encrypted recovery state, not plaintext summaries.
3. Existing useChat ALREADY subscribes to manager.getSnapshot and useConversationSession accepts a changing shared session. Review that selection notification rebinds subscribers correctly; no AuthContext/ConversationContext/transport rewrite is presumed necessary. Web can wire the existing action and history reader only after adapter approval.
4. A nonmutating read/decrypt capability may live on the initialized owner manager, using its existing authorized context, returning locked/unavailable if absent. Do not call getActiveCryptoContext from read-only History, generate keys, adopt older unverified sessions or expose raw material to Web code. This is a reviewed method addition, not unilateral crypto architecture work.

Important joint decision: New Chat must not bypass active crisis/handoff or exercise state. Initial safe proposal is refusing transition while those states are active until Ahmad confirms the correct existing safety-state continuation boundary. Do not reset classifier/policy/signed tokens merely to satisfy separate transcript context. Existing route navigation stays unrestricted as currently accepted. No risk policy changed by Web.

Required technical sign-off: additive archive schema; atomic checkpoint/archive/select and revision/cross-tab semantics; existing-key-only target validation; selected-session notification/refresh; safety/exercise busy behavior. Regression tests: 12-message A preserved -> fresh B with distinct ID and empty text context -> refresh lists both -> resume A and follow-up context -> resume B unchanged; streaming refusal leaves exactly one POST/key context; aborted/foreign/stale/locked/corrupt targets do not change active pointer; no completion or rewards. All protected patches remain unapplied until Ahmad + product owner jointly approve.

## Firebase preference investigation � 2026-10-18

See KOI_FIREBASE_PREFERENCE_SYNC_AUDIT_2026-10-18.md for current source/runtime comparison, exact Console checks, minimal conditional config/rule review, and local-vs-cloud dependency matrix. No Firebase rules/config/auth or protected P0 files changed. Owner Console session/published Rules/App Check enforcement are not available to this agent; requested nonsecret Rules text + project/database/enforcement evidence. Do not claim deployed parity from repository rules.

Real synthetic Firebase browser: anonymous signUp/lookup 200; Auth/Firestore same default app and configured project koi-companion-fyp; (default) database, same UID in actual users/{uid} update mask. Captured mask is onboarding_complete + profile.avatar/companion/language/notificationTime, merge may create or update. Own write AND own getDocFromServer reject permission-denied. Only UID fingerprint recorded, no token/keys/headers/document contents inspected. Client config alignment is not proof of token issuer/API-key project association; verify user and Web registration privately in Console.

Independent source gap: Settings/inline avatar/language preferences and their readers are local-only; fixing access does not wire subsequent account sync. Candidate accountPreferenceSync.proposed.ts implements owner-guarded existing-profile server get/merge with safe errors and SDK acknowledgement, language-only patch and legacy fox, no local/queue/crypto writes. Imported only by tests, NOT integrated before approval. No new disabled controls. Existing source firestore.rules already permits authenticated own user document, so no widening is proposed without deployed evidence. firebase.json lacks a firestore.rules reference; config mapping is proposal only.

Separate protected cloud-message path mismatch: conversationService queues conversations/{conversation UUID}/messages while source rules authorize conversations/{owner UID}/messages. Review minimal owner-path alignment and queue compatibility, not broad cross-user grants; no patch or replay applied. Current encrypted local P0 remains unchanged.

Local multi-chat, encrypted check-ins and local reward/progress ledgers need approved session/key/schema/provenance adapters, not new Firebase infrastructure. Cross-device key recovery and account-global transactional caps/verified issuance are separate shared-authority decisions. Do not put numeric plaintext check-ins into existing moodEntries merely because the schema exists. See audit for concrete review gates.

## Firebase deployment-policy diagnosis update � 2026-10-18

Owner supplied published temporary public rule expiring 5 June 2026; it denies all client access now and sufficiently explains the real anonymous own-document denial. Proposed replacement is restricted exact-owner user profile/crypto-metadata get/create/update, no public/all-authenticated wildcard or account delete; file review/firestore.user-preferences.proposed.rules, not deployed or referenced by firebase.json. This is a review proposal requiring approval/Rules engine tests, not a security bypass or policy already applied. App Check/Console target confirmation remains pending. Default and --proposal emulator test variants prepared; no emulator installed or run. See dedicated audit for exact Console steps, source ownership comparison and least-scope candidate. Client-only Jest/TS/Next results cannot establish Rules correctness.


## 2026-10-18 ? Preference synchronization implementation authorization

Product owner reports replacing expired Firestore Rules with authenticated users/{uid} ownership and explicitly authorizes wiring the reviewed preference adapter into Settings/inline switching and authenticated initialization/refresh. Implemented merge-only avatar/companion/language sync, persisted UID-row pending revisions, local-first offline behavior, guarded hydration, and truthful server status/Retry. No new schema/index/table, encryption change, security-rule/configuration change, or shared P0/renderer patch. Existing local choice wins on first integration; subsequently pending local edits win over account snapshots, acknowledged revisions clear atomically, and other account values hydrate locally. See implementation acceptance report for tests/browser evidence. This authorization does not grant joint technical approval for history switching, encrypted activity/rewards, restore writes or voice adapters.


## 2026-10-18 ? Increment 04 joint approval supersedes reward-disabled decisions

Owner reports Ahmad approved ADR-REWARDS/activity storage October 18 and supplies exact additive three-store contract. Implement locally; db.ts diff remains for Ahmad review before merge. No backend/cloud reward authority is claimed. Existing-key AES-GCM unchanged; no existing store/schema/record migration; activity/reward data excluded from syncQueue and portability. Version 3 adds only activityEvents, rewardReceipts, milestoneReceipts. See review/increment04-db-migration.diff, activityTypes.ts and activityLedger.ts for exact implementation.

Activity id and completion_id are identical; the explicit completion_id alias exists to satisfy the required unique compound index. IDs are globally unique; a cross-owner collision rejects without returning the other event. Reward primary key is JSON.stringify([owner_uid,source_type,day_key]); milestone key is JSON.stringify([owner_uid,milestone]). Unique indexes additionally enforce source/day, slot per owner, milestone per owner and owner/source/completion ID. Every read is owner-filtered (duplicate lookup uses the requested primary identity followed by strict owner check). One readwrite transaction covers all three stores. Duplicate add ConstraintError is caught inside that transaction and returns original event/receipt; any other failure aborts the transaction. Serialized overlapping IDB scopes plus unique indexes arbitrate tabs. SDK account-change notification aborts an active transaction; the captured owner is never replaced with a later UID.

Policy remains one piece per source/day in Asia/Karachi, 25 slots, milestones 5/10/15/20/25, event-only recording when capped/full, no retroactive conversion or inferred awards. Day keys explicitly assemble year/month/day from Intl formatToParts. Client clock is accepted for gamification, not authoritative security time. Provenance is an allowlisted scalar evidence object; breathing includes measurement='client-measured', durationMs, cycles and endReason. Ratings appear only in AES-GCM payload {scale_version,mood,connection,energy}; no free text or plaintext rating store/cache/log.

Check-in scale is 1?5 integers for Mood, Connection and Energy, using the exact owner-supplied DCW-9 terms; no unverified descriptive anchors or diagnosis. Form UUID is created on opening and held across retries; actual first save-attempt timestamp is retained through retries. Consent, three required ratings, existing owner and usable key are required. Existing anonymous crypto cache-hit path is reused only with a pre-existing secret and UID salt; no missing-key generation to unlock records. Linked-account unlock context is not exposed by existing AuthContext; linked check-ins remain honestly locked pending a scoped already-unlocked crypto capability. withOwnedDecryptor/history interface remains separately unapproved.

Breathing callback is additive in ExerciseDirector: onBreathingResult({sessionId,startedAt,endedAt,cyclesPlanned,cyclesCompleted,endReason,durationMs}). The owner gave implementation discretion in response to the durationMs request; no Ahmad confirmation beyond that reply is invented. durationMs uses the existing monotonic BreathingClock, excludes pause time, and must be >=48000; completed reason and >=ceil(0.8*cyclesPlanned) required. Identity is sha256('koi:breathing:v1:'+uid+':'+sessionId), independent of rotating exercise_state. The route's new context bridge supplies the callback without modifying Ahmad's CompanionScene/VRM/speech internals. Handoff/stop/navigation emit noneligible results; later state tokens do not resume the activity. Shipping audio remains disabled; no speech backend/lip-sync change.

**Specific remaining protected boundary: conversation completion.** SOURCE confirms conversationService persists an encrypted assistant with replyTo only after postJsonChat resolves; postJsonChat requires terminal done. Session status completed alone is insufficient because restore reconciles rows and serverEvents is reset at each later send. Current session exposes resolved-handoff keys but no durable authoritative unresolved-handoff state across turns/refresh. Never infer clearance from done.handoff:null, a numeric risk score, or missing latest-turn events. Safe explicit completion requires a narrow shared-owner getCompletionEvidence/withCompletionLease capability carrying owner,conversationId,pending,lastPersistedMessageId,persistedExchanges,turnState and handoffState='resolved-or-absent'|'unresolved'|'unknown', consistent for the save. A lease must prevent a new send/handoff change racing activity commit. Exact deterministic ID sha256('koi:conv:v1:'+uid+':'+conversationId+':'+lastPersistedMessageId) and fail-closed pure eligibility are implemented/tested independently, but no protected producer/session patch or runtime conversation reward is enabled. This is not a renewed blanket reward gate: real check-ins and verified breathing use the approved ledger.


### Increment 04 final clarification after interruption ? 2026-10-18

Approved reward/check-in implementation is present and 274 tests/39 suites plus TypeScript pass. Final authenticated frontend browser smoke 10/10 and separately labelled real-timed local breathing fixture 4/4 passed. Duplicate lookup is owner-filtered via the compound completion index. New check-in completed_at is actual save-attempt time after encryption, not an old form timestamp; existing completion retries keep the original event/time and never issue again. All activity/reward/milestone operations stay in the approved stores; old schemas/data, syncQueue and portability remain unchanged.

Only the specific completion-evidence/safety lease and linked existing-unlock activity capability remain joint interfaces. queueCrisisPath's queued resolution is not proof of server acknowledgement; missing/latest-turn handoff events cannot prove older handoffs resolved. No runtime conversation reward issued. Hosted Modal returned HTTP 200/done but no start_breathing directive, so hosted breathing completion is NOT RUN. Pure proof/25-slot/milestone tests and a local breathing fixture must not be called hosted acceptance. Exact db.ts and callback diffs remain for Ahmad before merge; no merge/commit/deployment made. Full final evidence and build identity in KOI_WEB_IMPLEMENTATION_ACCEPTANCE.md.


### ADR-HISTORY review-only update - 2026-10-18

Product owner explicitly retains Ahmad's joint approval requirement and authorizes preparation, not application, of the archive/session patch. Current branch feat/web-product-data, HEAD b384ce2cef44e83e53db7f50182f3ccfaac32187 plus all existing dirty work. No protected source changes applied. Authoritative package: repos/koi-backend/nextjs_app/review/new-chat-review.md, with exact session/consumer/test proposed diffs and source-hash manifest. Supersedes the earlier illustrative newChat/resume method sketch: reuse the already implemented ApprovedSessionTransitionAdapter instead of creating another abstraction. Proposed v4 adds conversationArchives keyed [uid+conversationId] and owner/time index [uid+lastActiveAt]; v1-v3 remain unchanged. No keys/ciphertext/auth/Firebase/reward changes performed.

Joint decisions still required: additive archive and atomic commit/cancellation/multi-tab review; unresolved-handoff transition guard (queued resolution is not acknowledged resolution); stale exercise recovery and linked existing-key compatibility. Storing old safety state is not by itself proof that an active handoff may be dismissed. Draft is not enablement-ready. Proposed tests and real A/B browser verification NOT RUN. Patch applicability, syntax and in-memory TypeScript PASS with unchanged source hashes. Independent existing consumer tests expanded to 11; full current-source Jest 286/39 PASS and TypeScript PASS. No production implementation or deployment claim.


### Final ownership transfer prepared - 2026-10-18

Ahmad is now sole KOI Web implementation owner. No new feature implementation in this transfer. See KOI_WEB_FINAL_HANDOFF_2026-10-18.md, KOI_WEB_FINAL_CONFLICT_REPORT_2026-10-18.md, KOI_WEB_FINAL_FILE_FUNCTION_INVENTORY_2026-10-18.json and KOI_WEB_WIP_STAGING_MANIFEST_2026-10-18.md for the authoritative actual-source inventory, exact proposed snapshot and blockers. Proposed handoff/web-product-data-2026-10-18 has NOT been created/committed/pushed; explicit manifest and push approval pending. Current source feat/web-product-data at b384ce2cef44e83e53db7f50182f3ccfaac32187 plus preserved dirty work. Ahmad remote fetched and verified at 884a278e0370835e98c07ae192cfa2dc8ba73495; no merge/cherry-pick.

Fresh tests: 286/39 Jest PASS (28.334s), TypeScript PASS, production build PASS 19/19, Next14.2.35 BUILD_ID i4JLGTu9EUai8YYGsixEA. No combined-branch or fresh browser acceptance. New Chat remains review-only/unapplied. Sole remaining transfer actions after approval are selective snapshot/branch push and actual SHA handoff; no parallel coding. 22 authored browser harnesses preserved as review copies with sanitized historical evidence summaries under nextjs_app/review/handoff-evidence. Raw runtime artifacts/environment/IDE/Android files excluded and untouched.

Security decision before push: existing tracked nextjs_app/.env.local.test contains service-account-shaped/private-key material. Non-disclosing local scan did not establish a parseable key or clearly synthetic identity. It is excluded from new staging, but unchanged tracked content remains inherited in branch/history. Ahmad/security owner must assess fixture status/credential disposition; no automatic deletion, rekey, rule edit or history rewrite. No secret value included in these reports.
