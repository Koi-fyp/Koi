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
 * §8, "Account Upgrade"):
 *
 *   1. ANONYMOUS phase: `secret` is a locally-generated random value,
 *      stored in this browser's localStorage. Device-local by design.
 *
 *   2. LINKED phase (after linkWithEmailAndPassword succeeds): `secret`
 *      becomes the user's password, entered at each session, never
 *      stored. All data encrypted during the anonymous phase must be
 *      re-encrypted under this new secret — see `reencryptOnLinking()`.
 *      🆕 NOT YET WIRED: nothing currently re-collects this password on a
 *      *returning* linked session (see AuthContext.tsx header comment).
 *      Callers must supply `linkedSecret` themselves until that exists.
 *
 * NOTE: "Master Password" as a separate standalone passphrase concept was
 * explicitly rejected. `secret` is always either the anonymous-phase
 * random value or the linked account's password.
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

/** Copy bytes into a definite ArrayBuffer for Web Crypto's BufferSource overloads. */
function copyToArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer;
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

export function getOrCreateAnonymousSecret(): string {
  const existing = localStorage.getItem(ANON_SECRET_STORAGE_KEY);
  if (existing) return existing;
  const generated = randomBase64(32);
  localStorage.setItem(ANON_SECRET_STORAGE_KEY, generated);
  return generated;
}

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
    false,
    ["encrypt", "decrypt"]
  );
}

// ---------- public encrypt / decrypt ----------

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
    copyToArrayBuffer(ciphertextWithMac)
  );

  return new TextDecoder().decode(plaintextBuf);
}

// ---------- linking migration ----------

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

export interface AuthState {
  /** From AuthContext's isLinked — true if this user has linked email/password. */
  isLinked: boolean;
  /**
   * Required when isLinked is true. The user's password for this session.
   * 🆕 Not currently sourced anywhere — see AuthContext.tsx header comment.
   * Caller must supply it once that session re-entry step exists.
   */
  linkedSecret?: string;
}

/**
 * 🆕 [SESSION FIX — see SESSION_HANDOFF.md §22.3 addition]
 *
 * Distinguishes WHY a salt fetch is blocked, so the UI layer can show one
 * of two distinct messages (locked decision, this session):
 *   - 'no-network'   → device has no connectivity at all
 *   - 'fetch-failed' → device reports online, but the Firestore read did
 *                      not succeed (flaky connection, captive portal,
 *                      transient server issue, etc.)
 */
export type SaltBlockedReason = 'no-network' | 'fetch-failed';

export class SaltFetchBlockedError extends Error {
  reason: SaltBlockedReason;
  constructor(reason: SaltBlockedReason) {
    super(`Salt fetch blocked: ${reason}`);
    this.name = 'SaltFetchBlockedError';
    this.reason = reason;
  }
}

/**
 * Returns the secret + salt to use for the current user's encrypt()/decrypt()
 * calls. Offline-first: local cache is checked before any network call.
 *
 * 🆕 [SESSION FIX] LOCKED BLOCK DECISION, implemented here:
 * A previously-linked user, on a device with no cached salt, who is
 * offline (or whose fetch fails despite looking online) is BLOCKED —
 * this throws SaltFetchBlockedError rather than silently generating a
 * fresh local salt. Silent generation in that specific case would
 * diverge from their real salt and break cross-device decryption later.
 *
 * Anonymous users are UNAFFECTED by this change — local salt generation
 * on first use remains correct behavior for them, same as before.
 * Already-synced devices going offline again are also UNAFFECTED — the
 * cache-hit path above returns immediately, same as before this fix.
 *
 * This function makes exactly ONE attempt. Retrying (auto-watch +
 * manual button, 5 attempts with backoff, per the locked UX decision) is
 * the caller's responsibility — see `resolveSaltWithRetry()` below, which
 * is what UI code should actually call.
 */
export async function getActiveCryptoContext(
  uid: string,
  authState: AuthState
): Promise<CryptoContext> {
  if (authState.isLinked && !authState.linkedSecret) {
    // Not a network/offline condition — a real caller-side bug (linked
    // user, but no session secret supplied). Fail loudly, not silently.
    throw new Error(
      'getActiveCryptoContext: authState.isLinked is true but no linkedSecret was supplied.'
    );
  }
  const secret = authState.isLinked
    ? (authState.linkedSecret as string)
    : getOrCreateAnonymousSecret();

  const cacheKey = `${SALT_CACHE_PREFIX}${uid}`;

  // 1. Local cache first.
  const cached = localStorage.getItem(cacheKey);
  if (cached) {
    return { secret, saltB64: cached };
  }

  // 2. No cache. This is the branch point for the locked block decision.
  const isOnline = typeof navigator !== 'undefined' ? navigator.onLine : false;

  if (authState.isLinked && !isOnline) {
    throw new SaltFetchBlockedError('no-network');
  }

  let existingSalt: string | undefined;
  try {
    if (!firestore) throw new Error('Firebase Firestore is not configured.');
    const userDocRef = doc(firestore, 'users', uid);
    const snapshot = await getDoc(userDocRef);
    existingSalt = snapshot.data()?.public_crypto_metadata?.salt as string | undefined;
  } catch {
    if (authState.isLinked) {
      throw new SaltFetchBlockedError('fetch-failed');
    }
    // Anonymous: unaffected by this fix, same fallback behavior as before.
    existingSalt = undefined;
  }

  if (existingSalt) {
    localStorage.setItem(cacheKey, existingSalt);
    return { secret, saltB64: existingSalt };
  }

  if (authState.isLinked) {
    // Reached only if Firestore responded successfully but genuinely has
    // no salt on record for a linked user — an inconsistent-account-state
    // case, not the offline case this fix targets. Block rather than
    // guess, same reasoning as above.
    throw new SaltFetchBlockedError('fetch-failed');
  }

  // 3. Brand new ANONYMOUS user only — generate, cache locally, queue the
  // Firestore write through the existing syncQueue. Unchanged from before
  // this fix.
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

/**
 * 🆕 [SESSION FIX] UI-facing retry driver for the locked block decision.
 *
 * Attempts getActiveCryptoContext() up to `maxAttempts` times (locked: 5),
 * with exponential backoff between attempts (1s, 2s, 4s, 8s — 4 waits
 * between 5 attempts). Intended to be triggered by EITHER a connectivity
 * "online" event listener OR a manual retry button — both drive the same
 * call, per the locked "auto-watch + manual button" decision. This
 * function does not register the listener or render the button itself;
 * that's UI-layer wiring (React component), kept separate from this
 * module's existing pattern of pure logic with no UI dependencies.
 *
 * `onAttempt` lets the caller update on-screen messaging per the locked
 * two-message decision: report the SaltBlockedReason from each failed
 * attempt so the UI can distinguish "no network" from "online, retrying"
 * while attempts are still in progress.
 */
export async function resolveSaltWithRetry(
  uid: string,
  authState: AuthState,
  onAttempt?: (attemptNumber: number, maxAttempts: number, reason: SaltBlockedReason) => void,
  maxAttempts: number = 5
): Promise<CryptoContext> {
  let lastReason: SaltBlockedReason = 'no-network';

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await getActiveCryptoContext(uid, authState);
    } catch (e) {
      if (!(e instanceof SaltFetchBlockedError)) {
        throw e; // Not our error to retry — propagate immediately.
      }
      lastReason = e.reason;
      onAttempt?.(attempt, maxAttempts, lastReason);

      if (attempt < maxAttempts) {
        const delayMs = 1000 * Math.pow(2, attempt - 1); // 1s, 2s, 4s, 8s
        await new Promise((resolve) => setTimeout(resolve, delayMs));
      }
    }
  }

  // All attempts exhausted — surface the final error state to the caller.
  throw new SaltFetchBlockedError(lastReason);
}


