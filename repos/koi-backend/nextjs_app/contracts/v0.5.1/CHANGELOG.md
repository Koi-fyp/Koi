# 0.5.1 ? WEB-2 additive extension

0.5.0 is byte-for-byte unchanged. Existing wire DTOs keep schema_version / contract_version 0.5.0. This additive package supplies roster and submission lists, a professional-only submission workspace, and explicit review decisions on new paths. Existing review POST/list shapes are unchanged. No AI worker or Flutter source changed; cross-track acknowledgement remains outstanding.

An evaluation envelope created on submission has empty scores/evidence and no interpretation. It permits manual review while the job is queued. It is not an AI result. Custom forms have no validated deterministic scoring. Decisions are separate append-only clinician revisions; neither original interpretation nor provider output is modified.

Invitation creation retries reconstruct a keyed 256-bit token from a random nonce; only its SHA-256 hash is persisted as token data. Nonces are not bearer secrets. Rotation of the signing secret invalidates reconstruction; issued token hashes continue validating. Secrets must be retained until invitation expiry to permit retries.

Patient registration remains blocked until approved mail possession challenges exist. Emulator fixtures seed fictional General accounts only. Applications use an explicitly shared psychologist UID, require current verified practice authority, and follow the frozen demo-only state machine. Discovery catalogue is deferred.

Capabilities remain capped at 200 active relationships. All lists use signed scope-bound cursors. Patient assignment pagination queries by authenticated patient UID and checks relationship authority for every returned candidate; closed records are omitted with an advancing cursor.
