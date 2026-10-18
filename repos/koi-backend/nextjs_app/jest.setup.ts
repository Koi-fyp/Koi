import '@testing-library/jest-dom';

// JSDOM omits randomUUID; production uses the browser's native secure UUID implementation.
import { webcrypto } from 'crypto';
import { Buffer } from 'buffer';
if (!globalThis.crypto.randomUUID) Object.defineProperty(globalThis.crypto, 'randomUUID', { configurable: true, value: webcrypto.randomUUID.bind(webcrypto) });

// Tests that install Node's webcrypto run it against buffers created in the jsdom realm. Node's
// BufferSource check accepts views from any realm but tests a raw ArrayBuffer against its own
// prototype, so a jsdom ArrayBuffer is rejected. Copy such buffers into a Node-realm ArrayBuffer;
// src/lib/crypto.ts and the ciphertext format are unchanged.
const NODE_REALM = Symbol.for('koi.test.nodeRealmSubtle');
const subtle = webcrypto.subtle as unknown as Record<string | symbol, unknown>;
if (!subtle[NODE_REALM]) {
  const nodeArrayBuffer = Object.getPrototypeOf(Buffer.alloc(0).buffer).constructor as ArrayBufferConstructor;
  const toNodeRealm = (value: unknown) => {
    if (value instanceof nodeArrayBuffer || Object.prototype.toString.call(value) !== '[object ArrayBuffer]') return value;
    const bytes = new Uint8Array(value as ArrayBuffer);
    const copy = Buffer.alloc(bytes.byteLength); copy.set(bytes);
    return copy.buffer.slice(copy.byteOffset, copy.byteOffset + copy.byteLength);
  };
  for (const name of ['encrypt', 'decrypt', 'digest', 'importKey', 'sign', 'verify', 'deriveBits', 'deriveKey', 'unwrapKey']) {
    const original = subtle[name] as (...args: unknown[]) => unknown;
    subtle[name] = (...args: unknown[]) => original.apply(webcrypto.subtle, args.map(toNodeRealm));
  }
  subtle[NODE_REALM] = true;
}
