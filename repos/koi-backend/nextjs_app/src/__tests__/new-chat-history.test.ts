/** @jest-environment jsdom */
// Real Dexie v4 + PersistentConversation. Crypto and inference are synthetic fixtures, not AES-GCM or Modal evidence.
import { webcrypto } from 'crypto';
import type { ChatRequest, ChatSendOptions, ChatServerEvent } from '@/lib/conversation/chatContract';
let mockUid = 'history-owner-a';
const mockAuthListeners = new Set<(user: { uid: string } | null) => void>();
jest.mock('dexie', () => jest.requireActual('../../node_modules/dexie/dist/dexie.js'));
jest.mock('@/lib/firebase', () => ({ firestore: null, auth: { get currentUser() { return { uid: mockUid, isAnonymous: true, providerData: [] }; } } }));
jest.mock('firebase/auth', () => ({ onAuthStateChanged: (_auth: unknown, fn: (user: { uid: string } | null) => void) => { mockAuthListeners.add(fn); return () => mockAuthListeners.delete(fn); } }));
jest.mock('@/lib/firestore/sync', () => ({ syncQueue: { enqueue: jest.fn() } }));
jest.mock('@/lib/crypto', () => ({
  ...jest.requireActual('@/lib/crypto'),
  getActiveCryptoContext: jest.fn(async (uid: string) => ({ secret: uid, saltB64: 'fixture' })),
  encrypt: async (text: string, secret: string) => 'fixture:' + btoa(secret + ':' + encodeURIComponent(text)),
  decrypt: async (text: string, secret: string) => { const value = atob(text.slice(8)); if (!value.startsWith(secret + ':')) throw new Error('wrong key'); return decodeURIComponent(value.slice(secret.length + 1)); },
}));
import { db } from '@/lib/db';
import { getActiveCryptoContext } from '@/lib/crypto';
import { syncQueue } from '@/lib/firestore/sync';
import { PersistentConversation, ConversationSwitchError } from '@/lib/conversation/PersistentConversation';
import { readArchivedConversations } from '@/lib/history/readArchive';
import { withOwnedDecryptor } from '@/lib/history/ownedDecryptor';

const HANDOFF = { to: 'crisis' as const, reason: 'synthetic-reason' };
const reply = { reply: 'Synthetic reply', companion_state: { emotion: 'neutral' as const, intensity: 0 }, latency_ms: 1 };
const requests: ChatRequest[] = [];
let events: ChatServerEvent[] = [];
let hold: Promise<void> | null = null;
const adapter = { send: jest.fn(async (request: ChatRequest, options: ChatSendOptions) => {
  requests.push(request);
  for (const event of events) options.onEvent?.(event);
  events = [];
  if (hold) { const wait = hold; hold = null; await wait; }
  return reply;
}) };
const managers: PersistentConversation[] = [];
async function owner(uid = mockUid) {
  const manager = new PersistentConversation(uid, adapter, { isLinked: false });
  managers.push(manager); await manager.initialize();
  if (!manager.session) throw new Error('not ready');
  return manager;
}
const reason = (promise: Promise<unknown>) => promise.then(() => 'resolved', (error: unknown) => error instanceof ConversationSwitchError ? error.reason : String(error));
const texts = (m: PersistentConversation) => m.session!.getSnapshot().messages.map(message => message.content);
async function dump() { const out: Record<string, unknown[]> = {}; for (const table of db.tables) out[table.name] = await table.toArray(); return JSON.stringify(out); }
beforeAll(() => { Object.defineProperty(globalThis, 'crypto', { configurable: true, value: webcrypto }); });
beforeEach(async () => {
  mockUid = 'history-owner-a'; mockAuthListeners.clear(); requests.length = 0; events = []; hold = null;
  adapter.send.mockClear(); jest.mocked(getActiveCryptoContext).mockClear(); jest.mocked(syncQueue.enqueue).mockClear();
  localStorage.clear(); localStorage.setItem('koi_anon_secret', mockUid); localStorage.setItem(`koi_salt_cache_${mockUid}`, 'fixture');
  for (const table of db.tables) await table.clear();
});
afterEach(() => { managers.splice(0).forEach(m => m.dispose()); });

it('A and B get distinct ids that persist across reload; History lists A from its encrypted header', async () => {
  const m = await owner(), a = m.session!.conversationId;
  await m.session!.send('Synthetic A first');
  const { conversationId: b } = await m.archiveAndStartNew(mockUid);
  expect(b).not.toBe(a); expect(texts(m)).toEqual([]);
  await m.session!.send('Synthetic B first');
  await m.checkpoint(); m.dispose(); const reloaded = await owner();
  expect(reloaded.session!.conversationId).toBe(b); expect(texts(reloaded)).toEqual(['Synthetic B first', 'Synthetic reply']);
  const archive = await readArchivedConversations(mockUid, new AbortController().signal);
  expect(archive.status).toBe('ready');
  expect(archive.conversations).toEqual([expect.objectContaining({ conversationId: a, locked: false, title: 'Synthetic A first', messageCount: 2 })]);
  expect(JSON.stringify(await db.conversationArchive.toArray())).not.toContain('Synthetic');
});

it('resume restores messages, context and signed exercise/crisis state', async () => {
  const m = await owner(), a = m.session!.conversationId;
  events = [{ event: 'state', data: { exercise_state: 'signed-exercise-token-A' } }, { event: 'handoff', data: HANDOFF }];
  await m.session!.send('Synthetic A first');
  m.session!.queueCrisisPath('reached_out', HANDOFF);
  await new Promise(resolve => setTimeout(resolve, 0));
  const before = m.session!.getSnapshot();
  await m.archiveAndStartNew(mockUid);
  expect(m.session!.getSnapshot().exerciseState).toBeNull();
  await m.session!.send('Synthetic B first');
  await m.activateArchived(mockUid, a);
  const resumed = m.session!.getSnapshot();
  expect(m.session!.conversationId).toBe(a);
  expect(resumed.messages.map(x => [x.id, x.content, x.status])).toEqual(before.messages.map(x => [x.id, x.content, x.status]));
  expect(resumed.exerciseState).toBe('signed-exercise-token-A');
  expect(resumed.policyPathPending).toBe('reached_out');
  expect(m.session!.isHandoffResolved(HANDOFF)).toBe(true);
  await m.session!.send('Synthetic A follow-up');
  const last = requests[requests.length - 1];
  expect(last.session_history).toEqual([{ role: 'user', content: 'Synthetic A first' }, { role: 'assistant', content: 'Synthetic reply' }]);
  expect(last).toMatchObject({ exercise_state: 'signed-exercise-token-A', policy_event: 'crisis_resolved', crisis_path: 'reached_out' });
  // B was archived intact and is listed; the active A is not duplicated in the archive.
  const archived = await db.conversationArchive.toArray();
  expect(archived.map(row => row.conversationId)).not.toContain(a);
  expect(archived).toHaveLength(1);
});

it('refuses New Chat and resume with busy while a reply is pending, without aborting or reposting it', async () => {
  let release!: () => void; const m = await owner(), a = m.session!.conversationId;
  hold = new Promise<void>(resolve => { release = resolve; });
  const sending = m.session!.send('Synthetic pending');
  while (!requests.length) await new Promise(resolve => setTimeout(resolve, 0));
  expect(await reason(m.archiveAndStartNew(mockUid))).toBe('busy');
  expect(await reason(m.activateArchived(mockUid, 'anything'))).toBe('busy');
  expect(m.session!.conversationId).toBe(a); expect(m.session!.getSnapshot().pending).toBe(true);
  release(); await sending;
  expect(adapter.send).toHaveBeenCalledTimes(1);
  expect(await db.conversationArchive.count()).toBe(0);
});

it('an empty current conversation is not archived, and a double click creates one conversation', async () => {
  const m = await owner(), a = m.session!.conversationId;
  expect(await m.archiveAndStartNew(mockUid)).toEqual({ conversationId: a, previousConversationId: a });
  expect(await db.conversationArchive.count()).toBe(0);
  await m.session!.send('Synthetic A');
  const results = await Promise.all([reason(m.archiveAndStartNew(mockUid)), reason(m.archiveAndStartNew(mockUid))]);
  expect(results.sort()).toEqual(['busy', 'resolved']);
  expect(await db.conversationArchive.count()).toBe(1);
});

it('an injected transaction failure keeps the old header, archive and session', async () => {
  const m = await owner(), a = m.session!.conversationId;
  await m.session!.send('Synthetic A');
  const hook = (mods: { conversationId?: string }, _key: unknown, old: { conversationId: string }) => {
    if (mods.conversationId && mods.conversationId !== old.conversationId) throw new Error('injected header failure');
  };
  db.conversations.hook('updating', hook);
  try { expect(await reason(m.archiveAndStartNew(mockUid))).toBe('storage-unavailable'); }
  finally { db.conversations.hook('updating').unsubscribe(hook); }
  expect((await db.conversations.get(mockUid))!.conversationId).toBe(a);
  expect(await db.conversationArchive.count()).toBe(0);
  expect(m.session!.conversationId).toBe(a); expect(m.getSnapshot().switching).toBe(false);
  await m.session!.send('Synthetic still works');
  expect(texts(m)).toContain('Synthetic still works');
});

it('a UID switch mid-swap writes no archive or new-owner rows and keeps the old selection', async () => {
  const m = await owner(), a = m.session!.conversationId;
  await m.session!.send('Synthetic A');
  const switching = reason(m.archiveAndStartNew(mockUid));
  mockUid = 'history-owner-b'; mockAuthListeners.forEach(fn => fn({ uid: mockUid }));
  expect(await switching).toBe('owner-changed');
  expect(await db.conversationArchive.count()).toBe(0);
  expect(await db.conversations.get('history-owner-b')).toBeUndefined();
  expect((await db.conversations.get('history-owner-a'))!.conversationId).toBe(a);
});

it('a stale second tab fails closed with conflict, including after A -> B -> A', async () => {
  const first = await owner(), a = first.session!.conversationId;
  await first.session!.send('Synthetic A');
  const stale = await owner();
  await first.archiveAndStartNew(mockUid); await first.session!.send('Synthetic B'); await first.activateArchived(mockUid, a);
  expect((await db.conversations.get(mockUid))!.conversationId).toBe(a);
  const header = await db.conversations.get(mockUid);
  expect(await reason(stale.archiveAndStartNew(mockUid))).toBe('conflict');
  expect(await db.conversations.get(mockUid)).toEqual(header);
  expect(stale.getSnapshot().error).toMatch(/Reload/);
});

it('a locked or corrupt archived target is refused and never replaces the current selection', async () => {
  const m = await owner(), a = m.session!.conversationId;
  await m.session!.send('Synthetic A'); await m.archiveAndStartNew(mockUid); await m.session!.send('Synthetic B');
  const b = m.session!.conversationId;
  await db.conversationArchive.update([mockUid, a], { encryptedState: 'fixture:' + btoa('another-key:{}') });
  expect(await reason(m.activateArchived(mockUid, a))).toBe('locked');
  expect(await reason(m.activateArchived(mockUid, 'missing-id'))).toBe('not-found');
  expect(m.session!.conversationId).toBe(b); expect((await db.conversations.get(mockUid))!.conversationId).toBe(b);
  const archive = await readArchivedConversations(mockUid, new AbortController().signal);
  expect(archive.conversations).toEqual([expect.objectContaining({ conversationId: a, locked: true, title: '', messageCount: null })]);
});

it('a missing device key reads History as locked with zero writes and no key creation', async () => {
  const m = await owner(); await m.session!.send('Synthetic A'); await m.archiveAndStartNew(mockUid);
  m.dispose(); jest.mocked(getActiveCryptoContext).mockClear(); jest.mocked(syncQueue.enqueue).mockClear();
  localStorage.removeItem('koi_anon_secret');
  const storageBefore = { ...localStorage }, rowsBefore = await dump();
  const archive = await readArchivedConversations(mockUid, new AbortController().signal);
  expect(archive.status).toBe('locked');
  expect(archive.conversations).toEqual([expect.objectContaining({ locked: true, messageCount: null })]);
  expect({ ...localStorage }).toEqual(storageBefore); expect(await dump()).toBe(rowsBefore);
  expect(getActiveCryptoContext).not.toHaveBeenCalled(); expect(syncQueue.enqueue).not.toHaveBeenCalled();
});

it('withOwnedDecryptor discards late plaintext on abort or UID change', async () => {
  const sample = 'fixture:' + btoa(mockUid + ':' + encodeURIComponent('Synthetic secret text'));
  const controller = new AbortController();
  const aborted = await withOwnedDecryptor(mockUid, controller.signal, async decryptOwned => { const text = decryptOwned(sample); controller.abort(); return text; });
  expect(aborted).toEqual({ status: 'unavailable', reason: 'aborted' });
  const switched = await withOwnedDecryptor(mockUid, new AbortController().signal, async decryptOwned => { const text = await decryptOwned(sample); mockUid = 'history-owner-b'; return text; });
  expect(switched).toEqual({ status: 'locked', reason: 'owner-unverified' });
  expect(JSON.stringify([aborted, switched])).not.toContain('Synthetic');
});

it('New Chat and resume issue zero completion or reward events', async () => {
  const m = await owner(), a = m.session!.conversationId;
  await m.session!.send('Synthetic A'); await m.archiveAndStartNew(mockUid); await m.session!.send('Synthetic B'); await m.activateArchived(mockUid, a);
  expect(await db.activityEvents.count()).toBe(0); expect(await db.rewardReceipts.count()).toBe(0); expect(await db.milestoneReceipts.count()).toBe(0);
  expect(jest.mocked(syncQueue.enqueue).mock.calls.filter(([item]) => /archive/i.test(item.collection))).toEqual([]);
});
