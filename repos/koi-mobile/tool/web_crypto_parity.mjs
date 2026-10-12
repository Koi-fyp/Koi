// KOI crypto parity tool (Prompt 3, Part A). PRE-CHECK ONLY — this does not
// close Gate 1-J, which is a joint live test against real Firestore data.
//
// The crypto functions below are copied from
// repos/koi-backend/nextjs_app/src/lib/crypto.ts (bufToBase64, base64ToBuf,
// deriveKey, encrypt, decrypt) with only the TypeScript type annotations
// removed. Do not redesign them: they must behave exactly like the web app.
// Node >= 20 provides the same globals the browser does (crypto.subtle,
// crypto.getRandomValues, TextEncoder/TextDecoder, btoa/atob).
//
// Usage:
//   node tool/web_crypto_parity.mjs generate <out.json>
//       Encrypt the fixed test cases with the web logic and write them.
//   node tool/web_crypto_parity.mjs verify <in.json>
//       Decrypt every case's `payload` with the web logic and compare it with
//       `plaintext`. Prints PASS/FAIL per case; exits 1 on any failure.

import { readFileSync, writeFileSync } from 'node:fs';

// ---------- copied from crypto.ts ----------

const PBKDF2_ITERATIONS = 600_000;
const NONCE_BYTES = 12; // AES-GCM standard nonce size
const FORMAT_VERSION = "v1";
const KDF_LABEL = "PBKDF2";

function bufToBase64(buf) {
  const bytes = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function base64ToBuf(b64) {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

async function deriveKey(secret, saltB64) {
  const saltBytes = base64ToBuf(saltB64);
  const secretBytes = new TextEncoder().encode(secret);

  const baseKey = await crypto.subtle.importKey(
    "raw",
    secretBytes,
    "PBKDF2",
    false,
    ["deriveKey"]
  );

  return crypto.subtle.deriveKey(
    {
      name: "PBKDF2",
      salt: saltBytes,
      iterations: PBKDF2_ITERATIONS,
      hash: "SHA-256",
    },
    baseKey,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"]
  );
}

async function encrypt(plaintext, secret, saltB64) {
  const key = await deriveKey(secret, saltB64);
  const nonce = crypto.getRandomValues(new Uint8Array(NONCE_BYTES));
  const encoded = new TextEncoder().encode(plaintext);

  const ciphertextWithMac = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: nonce },
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

async function decrypt(payload, secret) {
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
    { name: "AES-GCM", iv: nonce },
    key,
    ciphertextWithMac
  );

  return new TextDecoder().decode(plaintextBuf);
}

// ---------- end of copied code ----------

// Fixed TEST inputs (not product values).
// Anonymous-style secret: 32 bytes 0x00..0x1F, base64 — same shape as
// crypto.ts getOrCreateAnonymousSecret() (randomBase64(32)).
const ANON_SECRET = bufToBase64(Uint8Array.from({ length: 32 }, (_, i) => i));
// Linked-style secret: a password with non-ASCII characters, to exercise the
// UTF-8 encoding of the secret (TextEncoder on web, utf8.encode in Dart).
const LINKED_SECRET = "pässwörd-کوئی-🔑";
// Salt: 16 bytes 0xA0..0xAF, base64 — same shape as generateSalt().
const SALT = bufToBase64(Uint8Array.from({ length: 16 }, (_, i) => 0xa0 + i));

const CASES = [
  { name: "ascii", secret: ANON_SECRET, plaintext: "Hello, KOI! 123 :colons: ok" },
  { name: "urdu", secret: ANON_SECRET, plaintext: "آج میں بہت پریشان ہوں، لیکن میں ٹھیک ہو جاؤں گا۔" },
  { name: "emoji", secret: ANON_SECRET, plaintext: "😀👍🏽 🐟💙 👨‍👩‍👧 ✨" },
  { name: "empty", secret: ANON_SECRET, plaintext: "" },
  { name: "long_multiblock", secret: ANON_SECRET, plaintext: "KOI ".repeat(300) },
  { name: "linked_secret_mixed", secret: LINKED_SECRET, plaintext: "Mixed: hello / سلام / 🙂" },
];

async function generate(outPath) {
  const cases = [];
  for (const c of CASES) {
    const payload = await encrypt(c.plaintext, c.secret, SALT);
    cases.push({ name: c.name, secret: c.secret, salt: SALT, plaintext: c.plaintext, payload });
  }
  const doc = {
    description:
      "Web-generated KOI crypto test vectors. Produced by tool/web_crypto_parity.mjs " +
      "using logic copied from repos/koi-backend/nextjs_app/src/lib/crypto.ts. " +
      "Pre-check only; does not close Gate 1-J.",
    generator: `node ${process.version}`,
    cases,
  };
  writeFileSync(outPath, JSON.stringify(doc, null, 2) + "\n", "utf8");
  console.log(`wrote ${cases.length} cases to ${outPath}`);
}

async function verify(inPath) {
  const doc = JSON.parse(readFileSync(inPath, "utf8"));
  let failed = 0;
  for (const c of doc.cases) {
    try {
      const out = await decrypt(c.payload, c.secret);
      if (out === c.plaintext) {
        console.log(`PASS ${c.name}`);
      } else {
        failed++;
        console.log(`FAIL ${c.name}: decrypted text differs from plaintext`);
      }
    } catch (e) {
      failed++;
      console.log(`FAIL ${c.name}: ${e && e.name}: ${e && e.message}`);
    }
  }
  console.log(`${doc.cases.length - failed}/${doc.cases.length} passed`);
  process.exit(failed === 0 ? 0 : 1);
}

const [cmd, path] = process.argv.slice(2);
if (cmd === "generate" && path) await generate(path);
else if (cmd === "verify" && path) await verify(path);
else {
  console.error("usage: node tool/web_crypto_parity.mjs (generate|verify) <file.json>");
  process.exit(2);
}
