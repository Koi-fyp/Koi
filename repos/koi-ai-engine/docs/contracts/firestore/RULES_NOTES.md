# Proposed Firestore rules notes

## Basis

The proposal is derived only from
`docs\contracts\firestore\FIRESTORE_ACCESS_INVENTORY.md`. It permits the
observed `users/{uid}` top-level and nested keys, with owner checks and a
separate create rule. Unknown fields are rejected. The message write is
observed, but is denied until ownership can be verified.

## Existing configuration comparison

The backend already contains `repos\koi-backend\firestore.rules`,
`firebase.json`, and `.firebaserc`. The existing rules allow owner reads and
writes for:

* `users/{userId}`
* `conversations/{userId}/messages/{messageId}`
* `mood_entries/{userId}/entries/{entryId}`
* `wellness_progress/{userId}`
* `tasks/{userId}/items/{taskId}`

The proposal is **stricter** for `users`: it rejects unknown top-level and
nested keys, separates create from update, and checks the authenticated UID.
It is **stricter** for messages: existing rules allow access when the
conversation path segment equals the UID; the audited client only supplies an
arbitrary `conversationId` and the message has no owner field. The proposal
therefore denies access rather than asserting an unverified relationship.
The proposal is **stricter** for the other three existing paths because it
does not include them: no audited client code writes those paths. It is not
looser than the existing rules for any path.

`firebase.json` configures Functions and emulators but does not configure a
Firestore rules file. `.firebaserc` contains project/hosting/function target
metadata only. The proposal does not overwrite either file or the existing
`firestore.rules`.

Firebase CLI is installed (`firebase`/`firebase.cmd` found), but the proposal
is a standalone file and is not wired into `firebase.json`; it was **NOT
syntax-checked** to avoid changing or deploying the backend configuration.

## UNDECIDED — needs field list from mobile

* Mobile onboarding answers and settings fields not written by the audited
  client code must not be added to rules. The requested future onboarding
  answers/settings contract is UNDECIDED.
* Whether `conversationId` is guaranteed to equal the authenticated UID, or
  whether messages should carry a server/client-written owner field, is
  UNDECIDED. Options: use UID as the conversation path segment, add a
  protected owner field with create-time validation, or introduce a parent
  conversation document whose owner is checked.
* Whether Admin-created user documents should be exempt from client create
  constraints is UNDECIDED; Admin SDK bypasses rules in any case.

## What rules cannot protect

* An owner can write arbitrary ciphertext and any permitted scalar/map values;
  rules do not attest plaintext meaning or cryptographic correctness.
* Admin SDK writes in the two API routes bypass Firestore rules.
* Rules cannot recover an anonymous secret, re-encrypt ciphertext, or make
  local storage/device state durable.
* Without an owner-bearing message document or a contract tying the path ID to
  the UID, rules cannot safely prove message ownership.

