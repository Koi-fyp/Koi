# Client crypto audit

Audited at Web/Dart commit `fa223ae` (`2026-10-11 01:41:34 +0500`).

## Spec comparison

| Spec line | Result | Evidence |
|---|---|---|
| AES-GCM 256-bit | MATCH (Web and Dart) | Web `lib/crypto.ts:102-108` derives `{name:"AES-GCM", length:256}` and encrypts with AES-GCM. Dart `services/crypto_service.dart:31,90` uses `AesGcm.with256bits()`. |
| PBKDF2-HMAC-SHA256, 600,000 iterations | MATCH (Web and Dart) | Web `crypto.ts:37,101-106`: `PBKDF2_ITERATIONS = 600_000`, `hash:"SHA-256"`. Dart `crypto_service.dart:25,78-84`: `iterations: 600000`, `Hmac.sha256()`. |
| `v1:PBKDF2:base64(salt):base64(nonce):base64(ciphertext_with_mac)` | MATCH (implementation shape) | Web `crypto.ts:118-125`; Dart `crypto_service.dart:90-112` explicitly joins the five parts and appends the separate Dart MAC. Dart notes that byte-for-byte Gate 1-J verification is still pending. |
| Salt stored at `users/{uid}.public_crypto_metadata.salt` | PARTIAL / MISMATCH in Dart wiring | Web reads at `crypto.ts:280-282` and queues the write at `307-313`. Dart generates a salt at `crypto_service.dart:39-44` but contains no Firestore write or `uid` parameter in the crypto service. |
| Anonymous secret is random, device-local, not synced | MATCH (storage differs) | Web `crypto.ts:75-80` uses `localStorage`; Dart `crypto_service.dart:55-70` uses `FlutterSecureStorage`. Neither queues the secret. |
| Linked secret is per-session password, never stored | PARTIAL | Web documents the intended source at `crypto.ts:18-29` and requires `linkedSecret` at `crypto.ts:238-260`; `AuthContext.tsx:119-137` receives the password only for the link request and does not retain it. Dart passes the password to `linkWithCredential` (`auth_service.dart:96`) and does not persist it. |
| Anonymous ciphertext re-encrypted at linking | MISMATCH in active wiring | Web has a pure helper `reencryptOnLinking` at `crypto.ts:173-181`, but no caller was found. Dart has `clearAnonymousSecret` (`crypto_service.dart:67-71`) but no ciphertext migration or call from `AuthService.linkWithEmailAndPassword`. |

## Direct answers

1. The Web anonymous secret is in browser `localStorage` under
   `koi_anon_secret` (`crypto.ts:75-80`). The Dart equivalent is in platform
   `FlutterSecureStorage` under `koi_anon_secret` (`crypto_service.dart:55-70`).
2. Clearing that storage removes the secret. Existing ciphertext cannot be
   decrypted by the affected browser/device. A different browser/device has a
   different anonymous secret and cannot decrypt it. The Web salt cache is
   also local, although Web can fetch the salt from Firestore; the secret is
   not synced.
3. No recovery path for a lost anonymous secret was found. Linked sessions
   have no implemented password re-entry/unlock path in `AuthContext.tsx`;
   `getActiveCryptoContext` instead requires a caller-supplied `linkedSecret`.
4. The Web helper can re-encrypt payloads, but account-linking code never
   invokes it. Dart linking performs Firebase credential linking and writes
   metadata, but does not re-encrypt existing ciphertext. Therefore active
   code does **not** perform the required migration.
5. Web generates a 16-byte random salt in `crypto.ts:68-70` when an
   anonymous user's Firestore document has no salt (`crypto.ts:303-313`),
   caches it locally, and queues `users/{uid}.public_crypto_metadata.salt`.
   Web reads an existing salt at `280-282`. Dart has a generator at
   `crypto_service.dart:39-44`, but no observed call that writes that salt
   to Firestore.

No `.env*`, key file, service-account file, or secret value was read or
printed during this audit.

