const assert = require('node:assert/strict');
const fs = require('node:fs');
const Module = require('node:module');
const path = require('node:path');
const ts = require('typescript');
const { webcrypto } = require('node:crypto');

globalThis.crypto ??= webcrypto;
globalThis.btoa ??= (value) => Buffer.from(value, 'binary').toString('base64');
globalThis.atob ??= (value) => Buffer.from(value, 'base64').toString('binary');

require.extensions['.ts'] = (module, filename) => {
  const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    fileName: filename,
  }).outputText;
  module._compile(output, filename);
};

const originalLoad = Module._load;
Module._load = function (request, parent, isMain) {
  if (request === './firebase' && parent?.filename.endsWith(`${path.sep}src${path.sep}lib${path.sep}crypto.ts`)) {
    return { firestore: {} };
  }
  if (request === './firestore/sync' && parent?.filename.endsWith(`${path.sep}src${path.sep}lib${path.sep}crypto.ts`)) {
    return { syncQueue: {} };
  }
  return originalLoad.call(this, request, parent, isMain);
};

const { decrypt, encrypt } = require('../src/lib/crypto.ts');
const legacyFixture = 'v1:PBKDF2:AAECAwQFBgcICQoLDA0ODw==:EBESExQVFhcYGRob:699ne3yA8jqlUnoKHB567CT5cp8/Z70TZQ+bnun0bQfULFhsVjo10nID';

(async () => {
  const knownPlaintext = 'KOI legacy payload fixture';
  assert.equal(await decrypt(legacyFixture, 'fixture-password'), knownPlaintext);
  const newPayload = await encrypt(knownPlaintext, 'fixture-password', 'AAECAwQFBgcICQoLDA0ODw==');
  assert.equal(newPayload.split(':').length, 5);
  assert.equal(newPayload.split(':')[0], 'v1');
  assert.equal(newPayload.split(':')[1], 'PBKDF2');
  assert.equal(await decrypt(newPayload, 'fixture-password'), knownPlaintext);
  assert.notEqual(newPayload, legacyFixture, 'encryption must retain a fresh random nonce');
  console.log(JSON.stringify({ passed: true, checks: ['existing v1 payload decrypt fixture', 'AES-GCM encrypt/decrypt round-trip', 'serialized format/version preserved'] }));
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
}).finally(() => {
  Module._load = originalLoad;
});
