"use client";

import { firestore } from './firebase';
import { doc, getDoc, setDoc } from 'firebase/firestore';
import { syncQueue } from './firestore/sync';

/**
 * KOI client-side encryption — locked spec:
 *   - AES-256-GCM for encryption
 *   - PBKDF2-HMAC-SHA256, 600,000 iterations, for key derivation
 *   - Payload format: v1:PBKDF2:base64(salt):base64(nonce):base64(ciphertext_with_mac)
 *   - Salt lives in Firestore at users/{uid}.public_crypto_metadata.salt
 *
 * Trust model: CSE (client-side encryption) at rest, NOT E2EE. The salt is
 * public/server-visible by design — security rests entirely on `secret`
 * never leaving the client unencrypted.
 *
 * LOCKED DECISION — secret source (resolved via KOI_UX_FLOWS_LOCKED_v1_1.md
 * §8, "Account Upgrade": linking is optional, not mandatory onboarding;
 * cross-device sign-in is explicitly a consequence of linking, not
 * available to anonymous users. Encryption follows the same shape:
 *
 *   1. ANONYMOUS phase: `secret` is a locally-generated random value,
 *      stored in this browser's localStorage. Device-local by design —
 *      matches the fact that anonymous users have no cross-device sign-in
 *      either, per §8. This is NOT a bug; it's the intended MVP boundary.
 *
 *   2. LINKED phase (after linkWithEmailAndPassword succeeds): `secret`
 *      becomes the user's password, entered at each session, never
 *      stored. All data encrypted during the anonymous phase must be
 *      re-encrypted under this new secret — see `reencryptOnLinking()`.
 *
 * Both phases use the exact same PBKDF2 + AES-GCM + versioned-format
 * pipeline below — only the source of `secret` differs.
 *
 * NOTE: "Master Password" as a separate standalone passphrase concept
 * was considered and explicitly rejected — see chat discussion. There is
 * no dedicated app-specific passphrase; `secret` is always either the
 * anonymous-phase random value or the linked account's password.
 */

const PBKDF2_ITERATIONS = 600_000;
const SALT_BYTES = 16;
const NONCE_BYTES = 12; // AES-GCM standard nonce size
const FORMAT_VERSION = "v1";
const KDF_LABEL = "PBKDF2";
const ANON_SECRET_STORAGE_KEY = "koi_anon_secret";
const SALT_CACHE_PREFIX = "koi_salt_cache_";

// ---------- encoding helpers ----------

function bufToBase64(buf: ArrayBuffer | Uint8Array): string {
  const bytes = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function base64ToBuf(b64: string): Uint8Array {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function randomBase64(byteLength: number): string {
  const bytes = crypto.getRandomValues(new Uint8Array(byteLength));
  return bufToBase64(bytes);
}

// ---------- salt ----------

/** Generates a new random salt. Persist to users/{uid}.public_crypto_metadata.salt. */
export function generateSalt(): string {
  return randomBase64(SALT_BYTES);
}

// ---------- anonymous-phase secret ----------

/**
 * Returns this device's anonymous-phase secret, generating and persisting
 * one to localStorage on first call. Device-local and intentionally NOT
 * synced — matches §8's "no cross-device until linking" behavior.
 */
export function getOrCreateAnonymousSecret(): string {
  const existing = localStorage.getItem(ANON_SECRET_STORAGE_KEY);
  if (existing) return existing;
  const generated = randomBase64(32);
  localStorage.setItem(ANON_SECRET_STORAGE_KEY, generated);
  return generated;
}

/** Call after successful migration in reencryptOnLinking() to remove the
 * now-obsolete anonymous secret. Do NOT call before migration completes. */
export function clearAnonymousSecret(): void {
  localStorage.removeItem(ANON_SECRET_STORAGE_KEY);
}

// ---------- key derivation ----------

async function deriveKey(secret: string, saltB64: string): Promise<CryptoKey> {
  const saltBytes = base64ToBuf(saltB64);
  const secretBytes = new TextEncoder().encode(secret);

  const baseKey = await crypto.subtle.importKey(
    "raw",
    secretBytes as BufferSource,
    "PBKDF2",
    false,
    ["deriveKey"]
  );

  return crypto.subtle.deriveKey(
    {
      name: "PBKDF2",
      salt: saltBytes as BufferSource,
      iterations: PBKDF2_ITERATIONS,
      hash: "SHA-256",
    },
    baseKey,
    { name: "AES-GCM", length: 256 },
    false, // not extractable — key material never leaves this derivation
    ["encrypt", "decrypt"]
  );
}

// ---------- public encrypt / decrypt ----------

/**
 * Encrypts `plaintext` under a key derived from `secret` + `saltB64`.
 * Returns: v1:PBKDF2:base64(salt):base64(nonce):base64(ciphertext_with_mac)
 *
 * Web Crypto's AES-GCM output already appends the auth tag to the
 * ciphertext, so the final segment already IS ciphertext_with_mac.
 */
export async function encrypt(
  plaintext: string,
  secret: string,
  saltB64: string
): Promise<string> {
  const key = await deriveKey(secret, saltB64);
  const nonce = crypto.getRandomValues(new Uint8Array(NONCE_BYTES));
  const encoded = new TextEncoder().encode(plaintext);

  const ciphertextWithMac = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: nonce as BufferSource },
    key,
    encoded
  );

  return [
    FORMAT_VERSION,
    KDF_LABEL,
    saltB64,
    bufToBase64(nonce),
    bufToBase64(ciphertextWithMac),
  ].join(":");
}

/**
 * Decrypts a payload produced by `encrypt()`. Parses and validates the
 * versioned format, failing loudly on anything malformed or unrecognized
 * rather than guessing.
 */
export async function decrypt(payload: string, secret: string): Promise<string> {
  const parts = payload.split(":");
  if (parts.length !== 5) {
    throw new Error(
      `Malformed KOI crypto payload: expected 5 colon-separated parts, got ${parts.length}`
    );
  }

  const [version, kdf, saltB64, nonceB64, ciphertextB64] = parts;

  if (version !== FORMAT_VERSION) {
    throw new Error(`Unsupported payload version: "${version}" (expected "${FORMAT_VERSION}")`);
  }
  if (kdf !== KDF_LABEL) {
    throw new Error(`Unsupported KDF label: "${kdf}" (expected "${KDF_LABEL}")`);
  }

  const key = await deriveKey(secret, saltB64);
  const nonce = base64ToBuf(nonceB64);
  const ciphertextWithMac = base64ToBuf(ciphertextB64);

  const plaintextBuf = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: nonce as BufferSource },
    key,
    ciphertextWithMac
  );

  return new TextDecoder().decode(plaintextBuf);
}

// ---------- linking migration ----------

/**
 * Re-encrypts every payload from the anonymous-phase secret to the new
 * password-derived secret. Call this once, immediately after
 * AuthService.linkWithEmailAndPassword() succeeds, BEFORE clearing the
 * anonymous secret from localStorage.
 *
 * Caller is responsible for:
 *   1. Fetching every stored encrypted payload for this user.
 *   2. Calling this function to get the re-encrypted versions.
 *   3. Writing the re-encrypted payloads back to Firestore/local storage.
 *   4. Updating users/{uid}.public_crypto_metadata.salt to newSaltB64.
 *   5. Only THEN calling clearAnonymousSecret().
 *
 * If any step 3 write fails partway through, do NOT clear the anonymous
 * secret — the old payloads are still decryptable with it, so a retry
 * remains possible. Clearing it early on partial failure is unrecoverable.
 */
export async function reencryptOnLinking(
  payloads: string[],
  anonymousSecret: string,
  newSecret: string,
  newSaltB64: string
): Promise<string[]> {
  const results: string[] = [];
  for (const payload of payloads) {
    const plaintext = await decrypt(payload, anonymousSecret);
    const reencrypted = await encrypt(plaintext, newSecret, newSaltB64);
    results.push(reencrypted);
  }
  return results;
}

// ---------- active crypto context ----------

export interface CryptoContext {
  secret: string;
  saltB64: string;
}

/**
 * Returns the secret + salt to use for the current user's encrypt()/decrypt()
 * calls. Offline-first, matching the pattern already established in
 * sync.ts — local cache is checked before any network call, and salt
 * writes go through the existing syncQueue rather than a new mechanism.
 *
 * CURRENT SCOPE — anonymous-phase only. This does not check whether the
 * user has linked an email/password, because the web app's linking flow
 * (AuthContext.tsx) hasn't been reviewed yet. Once linking exists here,
 * this needs a branch: linked users' `secret` becomes their password
 * instead of getOrCreateAnonymousSecret(), and reencryptOnLinking() must
 * run at the moment linking succeeds. Flagging rather than guessing at
 * unreviewed auth code.
 *
 * ⚠️ KNOWN OPEN GAP, DEFERRED TO END-OF-SESSION DOC UPDATE — NOT FIXED:
 * If this device has never cached a salt for this uid AND is offline on
 * this first call, there's no way to know whether a salt already exists
 * remotely (e.g. this is a returning linked user opening the app on a
 * new device before ever syncing). Generating a fresh local salt in that
 * case would silently diverge from their real salt and break cross-device
 * decryption later. This function currently generates locally in that
 * situation, which is safe for brand-new anonymous users but NOT provably
 * safe for a returning user's first-ever offline session on a new device.
 * Needs a UX decision (block/warn vs. silent generation) before this is
 * fully correct — not just a code fix. See SESSION_HANDOFF for tracking.
 */
export async function getActiveCryptoContext(uid: string): Promise<CryptoContext> {
  const secret = getOrCreateAnonymousSecret();
  const cacheKey = `${SALT_CACHE_PREFIX}${uid}`;

  // 1. Local cache first — matches offline-first pattern, avoids a
  //    network round-trip on every single message send/load.
  const cached = localStorage.getItem(cacheKey);
  if (cached) {
    return { secret, saltB64: cached };
  }

  // 2. Not cached — try Firestore, but don't let a network failure here
  //    block the user from sending a message at all.
  let existingSalt: string | undefined;
  try {
    const userDocRef = doc(firestore, 'users', uid);
    const snapshot = await getDoc(userDocRef);
    existingSalt = snapshot.data()?.public_crypto_metadata?.salt as string | undefined;
  } catch {
    // Offline or Firestore unreachable — see KNOWN OPEN GAP above.
    existingSalt = undefined;
  }

  if (existingSalt) {
    localStorage.setItem(cacheKey, existingSalt);
    return { secret, saltB64: existingSalt };
  }

  // 3. Brand new — generate, cache locally immediately (so encryption
  //    works right now regardless of network), then queue the Firestore
  //    write through the existing syncQueue so it retries automatically
  //    if we're currently offline, same as messages/mood data do.
  const saltB64 = generateSalt();
  localStorage.setItem(cacheKey, saltB64);

  syncQueue.enqueue({
    collection: 'users',
    docId: uid,
    data: { public_crypto_metadata: { salt: saltB64 } },
    priority: 4,
  });

  return { secret, saltB64 };
}
