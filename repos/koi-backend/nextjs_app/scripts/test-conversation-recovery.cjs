const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const ts = require('typescript');
const { webcrypto } = require('node:crypto');
globalThis.crypto ??= webcrypto;
require('fake-indexeddb/auto');
require.extensions['.ts'] = (module, filename) => module._compile(ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
}).outputText, filename);
const originalLoad = Module._load;
const account = { currentUser: { uid: 'fixture-a', isAnonymous: true, providerData: [], getIdToken: async () => 'synthetic-test-token' } };
const contexts = uid => ({ secret: `synthetic-${uid}`, saltB64: 'AAECAwQFBgcICQoLDA0ODw==' });
let realCrypto;
Module._load = function(request, parent, main) {
  if (request.endsWith('/firebase') || request === './firebase') return { auth: account, firestore: {} };
  if (request.endsWith('/firestore/sync')) return { syncQueue: { enqueue: item => { assert.match(item.data.content, /^v1:PBKDF2:/); } } };
  if (request === '../crypto') return { ...realCrypto, getActiveCryptoContext: async uid => contexts(uid) };
  return originalLoad.call(this, request, parent, main);
};
realCrypto = require('../src/lib/crypto.ts');
process.env.NEXT_PUBLIC_KOI_API_BASE = 'http://fixture.invalid';
const checks = [];
(async () => {
  // Upgrade a real v1 database, preserving ownerless ciphertext untouched.
  const Dexie = require('dexie');
  const legacy = new Dexie('KoiDB');
  legacy.version(1).stores({ users: '++id, uid', messages: 'id, conversationId, synced, timestamp', moodEntries: 'id, userId, synced, timestamp', jigsawProgress: 'uid', syncQueue: '++id, priority, createdAt' });
  await legacy.messages.put({ id: 'legacy-orphan', conversationId: 'legacy', content: 'untouched-ciphertext', timestamp: new Date(), sender: 'user', synced: false });
  legacy.close();
  const { db } = require('../src/lib/db.ts');
  const { PersistentConversation } = require('../src/lib/conversation/PersistentConversation.ts');
  const { sendMessage } = require('../src/lib/conversation/conversationService.ts');
  let postCount = 0; const requests = [];
  let release, streamed = false, slow = false;
  globalThis.fetch = async (_, init) => {
    postCount++; requests.push(JSON.parse(init.body));
    const encoder = new TextEncoder();
    return new Response(new ReadableStream({ async start(controller) {
      controller.enqueue(encoder.encode('event: delta\ndata: {"text":"Synthetic partial"}\n\n'));
      streamed = true;
      if (slow) await new Promise(resolve => { release = resolve; });
      controller.enqueue(encoder.encode('event: state\ndata: {"exercise_state":"opaque-signed-fixture"}\n\nevent: done\ndata: {"full_text":"Synthetic final","total_generation_s":1,"companion_state":{"emotion":"joy","intensity":0.6},"exercise_state":"opaque-signed-fixture"}\n\n'));
      controller.close();
    } }), { headers: { 'content-type': 'text/event-stream' } });
  };
  function manager(uid) {
    let owner;
    owner = new PersistentConversation(uid, { send: (request, options) => sendMessage(uid, owner.session.conversationId, request.message, request.session_history,
      { isLinked: false }, options, { exercise_state: request.exercise_state }) }, { isLinked: false });
    return owner;
  }
  const a = manager('fixture-a'); await a.initialize(); assert.equal(a.getSnapshot().error, null);
  const id = a.session.conversationId;
  assert.deepEqual(a.session.getSnapshot().messages, []);
  assert.equal((await db.messages.get('legacy-orphan')).content, 'untouched-ciphertext');
  checks.push('real Dexie v1 to v2 additive upgrade; legacy ciphertext retained and never adopted');
  await a.session.send('Synthetic first'); await a.checkpoint();
  assert.equal(a.session.getSnapshot().messages.length, 2);
  assert(a.session.getSnapshot().messages.every(m => m.status === 'completed'));
  const firstIds = a.session.getSnapshot().messages.map(m => m.id);
  let row = await db.conversations.get('fixture-a');
  assert.match(row.encryptedState, /^v1:PBKDF2:/);
  assert(!JSON.stringify(row).includes('Synthetic'));
  for (const message of await db.messages.where('conversationId').equals(id).toArray()) {
    assert.equal(message.ownerUid, 'fixture-a'); assert.match(message.content, /^v1:PBKDF2:/);
  }
  checks.push('actual AES-GCM/PBKDF2 encryption of session snapshot and actual service message rows; ciphertext-only sync');
  a.dispose(); db.close(); await db.open();
  const restored = manager('fixture-a'); await restored.initialize();
  assert.equal(restored.session.conversationId, id);
  assert.deepEqual(restored.session.getSnapshot().messages.map(m => m.id), firstIds);
  assert.equal(restored.session.getSnapshot().exerciseState, 'opaque-signed-fixture');
  await restored.session.send('Synthetic follow-up'); await restored.checkpoint();
  assert.equal(requests[1].session_history.length, 2);
  assert.deepEqual(requests[1].session_history.map(m => m.role), ['user', 'assistant']);
  checks.push('close/reopen IndexedDB and owner rehydrate original IDs, signed state and valid follow-up context');
  slow = true; streamed = false;
  const ongoing = restored.session.send('Synthetic during navigation');
  while (!streamed) await new Promise(resolve => setTimeout(resolve, 5));
  const off = restored.session.subscribe(() => {}); off(); // route leaves; owner remains
  assert.equal(restored.session.getSnapshot().pending, true);
  assert.equal(postCount, 3); release(); await ongoing; await restored.checkpoint();
  assert.equal(restored.session.getSnapshot().messages.length, 6); assert.equal(postCount, 3);
  checks.push('actual SSE transport survives absent route subscribers with one POST and one final bubble');
  // Simulate refresh after service committed a reply but before the snapshot checkpoint.
  const current = await db.conversations.get('fixture-a');
  const decoded = JSON.parse(await realCrypto.decrypt(current.encryptedState, contexts('fixture-a').secret));
  decoded.snapshot.messages = decoded.snapshot.messages.slice(0, 4); decoded.snapshot.pending = true;
  const encryptedState = await realCrypto.encrypt(JSON.stringify(decoded), contexts('fixture-a').secret, contexts('fixture-a').saltB64);
  restored.dispose(); await db.conversations.put({ ...current, encryptedState });
  const reconcile = manager('fixture-a'); await reconcile.initialize();
  assert.equal(reconcile.session.getSnapshot().messages.length, 6);
  assert(reconcile.session.getSnapshot().messages.every(m => m.status === 'completed'));
  assert.equal(reconcile.session.getSnapshot().error, null);
  assert.equal(reconcile.session.getSnapshot().companion.emotion, 'joy');
  checks.push('service commit/snapshot crash race reconciles owned encrypted rows without duplicate IDs');
  reconcile.dispose();
  account.currentUser = { ...account.currentUser, uid: 'fixture-b' };
  const b = manager('fixture-b'); await b.initialize(); assert.notEqual(b.session.conversationId, id);
  assert.deepEqual(b.session.getSnapshot().messages, []); b.dispose();
  const wrong = await db.conversations.get('fixture-b');
  await db.conversations.put({ ...wrong, encryptedState: current.encryptedState });
  const corrupt = manager('fixture-b'); await corrupt.initialize(); assert(corrupt.getSnapshot().error); assert.equal(corrupt.session, null); corrupt.dispose();
  checks.push('cross-account isolation and AES-GCM wrong-owner decryption fail closed');
  db.close();
  console.log(JSON.stringify({ passed: true, checks, scope: 'Real local encryption, IndexedDB and SSE parser; synthetic auth and fetch only, no network.' }, null, 2));
})().catch(error => { console.error('Conversation recovery fixture failed:', error.name, (error.stack ?? '').split('\n').filter(line => line.trim().startsWith('at ')).slice(0, 3).join('\n')); process.exitCode = 1; });
