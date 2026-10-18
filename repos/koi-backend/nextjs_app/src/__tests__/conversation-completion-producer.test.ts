/** @jest-environment node */
// Real Dexie + real conversationService/PersistentConversation; transport and crypto are synthetic fixtures.
import { webcrypto } from 'crypto';
import { TextEncoder } from 'util';
import type { ChatRequest, ChatSendOptions, ChatServerEvent } from '@/lib/conversation/chatContract';
let mockUid = 'completion-owner-a';
type Turn = { handoff?: { to: 'crisis'; reason: string } | null; standaloneHandoff?: boolean; fail?: Error; hold?: Promise<void>; skipDone?: boolean };
const mockTurns: Turn[] = [];
const mockRequests: ChatRequest[] = [];
jest.mock('dexie', () => jest.requireActual('../../node_modules/dexie/dist/dexie.js'));
jest.mock('@/lib/firebase', () => ({ firestore: null, auth: { get currentUser() { return { uid: mockUid, isAnonymous: true, providerData: [], getIdToken: async () => 'synthetic-token' }; } } }));
jest.mock('firebase/auth', () => ({ onAuthStateChanged: () => () => {} }));
jest.mock('@/lib/firestore/sync', () => ({ syncQueue: { enqueue: jest.fn() } }));
jest.mock('@/lib/crypto', () => ({
  getActiveCryptoContext: async (uid: string) => ({ secret: uid, saltB64: 'fixture' }),
  encrypt: async (text: string, secret: string) => 'fixture:' + btoa(secret + ':' + encodeURIComponent(text)),
  decrypt: async (text: string, secret: string) => { const value = atob(text.slice(8)); if (!value.startsWith(secret + ':')) throw new Error('wrong owner'); return decodeURIComponent(value.slice(secret.length + 1)); },
}));
jest.mock('@/lib/conversation/jsonChatTransport', () => ({
  chatEndpoint: () => 'https://koi.example.test/chat',
  postJsonChat: async (request: ChatRequest, options: { signal: AbortSignal; onEvent: (event: ChatServerEvent) => void }) => {
    mockRequests.push(request);
    const turn = mockTurns.shift() ?? {};
    options.onEvent({ event: 'delta', data: { text: 'Synthetic reply' } });
    if (turn.standaloneHandoff && turn.handoff) options.onEvent({ event: 'handoff', data: turn.handoff });
    if (turn.hold) await turn.hold;
    options.signal.throwIfAborted();
    if (turn.fail) throw turn.fail;
    if (!turn.skipDone) options.onEvent({ event: 'done', data: { full_text: 'Synthetic reply', companion_state: { emotion: 'neutral', intensity: 0 }, handoff: turn.handoff ?? null } });
    return { reply: 'Synthetic reply', companion_state: { emotion: 'neutral', intensity: 0 }, latency_ms: 1 };
  },
}));
import { db } from '@/lib/db';
import { syncQueue } from '@/lib/firestore/sync';
import { sendMessage } from '@/lib/conversation/conversationService';
import { PersistentConversation } from '@/lib/conversation/PersistentConversation';
import { getQualifyingPair } from '@/lib/conversation/persistedEvidence';
import { saveConversationCompletion } from '@/lib/activities/conversationCompletion';

const HANDOFF = { to: 'crisis' as const, reason: 'synthetic-reason' };
const managers: PersistentConversation[] = [];
async function owner(uid = mockUid) {
  const manager: PersistentConversation = new PersistentConversation(uid, { send: (request: ChatRequest, options: ChatSendOptions) => sendMessage(uid, manager.session!.conversationId,
    request.message, request.session_history, { isLinked: false }, options, { exercise_state: request.exercise_state, client_event: request.client_event,
      policy_event: request.policy_event, crisis_path: request.crisis_path }) }, { isLinked: false });
  managers.push(manager); await manager.initialize();
  if (!manager.session) throw new Error('not ready');
  return manager;
}
const settled = async (manager: PersistentConversation) => { for (let i = 0; i < 5; i++) await new Promise(resolve => setTimeout(resolve, 0)); return manager.getSnapshot(); };
const aiRows = async () => (await db.messages.toArray()).filter(row => row.sender === 'ai');
beforeAll(() => { Object.defineProperty(globalThis, 'crypto', { configurable: true, value: webcrypto }); Object.assign(globalThis, { TextEncoder }); });
beforeEach(async () => {
  mockUid = 'completion-owner-a'; mockTurns.length = 0; mockRequests.length = 0; jest.mocked(syncQueue.enqueue).mockClear();
  jest.spyOn(Date, 'now').mockReturnValue(Date.parse('2026-10-19T08:00:00.000Z'));
  for (const table of db.tables) await table.clear();
});
afterEach(() => { managers.splice(0).forEach(manager => manager.dispose()); jest.restoreAllMocks(); });

describe('local turn evidence on AI rows', () => {
  it('stores handoff_open and done_seen on the local AI row only, never in the sync payload', async () => {
    const m = await owner();
    mockTurns.push({ handoff: HANDOFF }); await m.session!.send('Synthetic hello');
    const [row] = await aiRows();
    expect(row).toMatchObject({ handoff_open: true, done_seen: true, ownerUid: mockUid });
    const payloads = jest.mocked(syncQueue.enqueue).mock.calls.map(([item]) => item.data);
    expect(payloads).toHaveLength(2);
    for (const data of payloads) { expect(data).not.toHaveProperty('handoff_open'); expect(data).not.toHaveProperty('done_seen'); expect(JSON.stringify(data)).not.toContain('Synthetic'); }
  });
  it.each([
    ['failed', { fail: new Error('synthetic transport failure') }],
    ['interrupted stream', { fail: new Error('The companion stream ended before the turn completed.') }],
    ['resolved without a terminal done', { skipDone: true }],
  ] as const)('a %s turn writes no AI row', async (_label, turn) => {
    const m = await owner(); mockTurns.push(turn);
    await m.session!.send('Synthetic message');
    expect(await aiRows()).toHaveLength(0);
    expect(m.session!.getSnapshot().messages.find(message => message.sender === 'user')!.status).toBe('failed');
    expect(await getQualifyingPair(mockUid, m.session!.conversationId)).toBeNull();
  });
  it('a cancelled turn writes no AI row, and recovery after reload adopts none', async () => {
    let release!: () => void; const m = await owner();
    mockTurns.push({ hold: new Promise<void>(resolve => { release = resolve; }) });
    const sending = m.session!.send('Synthetic message');
    while (!mockRequests.length) await new Promise(resolve => setTimeout(resolve, 0));
    m.session!.cancel(); release(); await sending; await settled(m);
    expect(await aiRows()).toHaveLength(0);
    m.dispose(); const reloaded = await owner();
    expect(reloaded.session!.getSnapshot().messages.filter(message => message.sender === 'ai')).toHaveLength(0);
    expect(reloaded.getSnapshot().hasQualifyingPair).toBe(false);
  });
});

describe('durable unresolved handoff', () => {
  it('stays open across dialog close, navigation, benign handoff turns and an aborted resolve; clears only on a later null handoff', async () => {
    const m = await owner();
    mockTurns.push({ handoff: HANDOFF, standaloneHandoff: true }); await m.session!.send('Synthetic first');
    expect((await settled(m)).hasUnresolvedHandoff).toBe(true);
    // Closing the dialog is UI only; navigation remounts the owner from storage.
    m.dispose(); const n = await owner();
    expect(n.getSnapshot().hasUnresolvedHandoff).toBe(true);
    mockTurns.push({ handoff: HANDOFF }); await n.session!.send('Synthetic benign');
    expect((await settled(n)).hasUnresolvedHandoff).toBe(true);
    // Resolution selection whose request is aborted never clears it.
    let release!: () => void;
    n.session!.queueCrisisPath('reached_out', HANDOFF);
    mockTurns.push({ hold: new Promise<void>(resolve => { release = resolve; }) });
    const aborted = n.session!.send('Synthetic resolve attempt');
    while (mockRequests.length < 3) await new Promise(resolve => setTimeout(resolve, 0));
    expect(mockRequests[2]).toMatchObject({ policy_event: 'crisis_resolved', crisis_path: 'reached_out' });
    n.session!.cancel(); release(); await aborted;
    expect((await settled(n)).hasUnresolvedHandoff).toBe(true);
    // A later completed turn returning handoff null clears it.
    mockTurns.push({ handoff: null }); await n.session!.send('Synthetic after resolution');
    expect((await settled(n)).hasUnresolvedHandoff).toBe(false);
  });
});

describe('explicit conversation completion (ADR-REWARDS matrix)', () => {
  const counts = async () => ({ events: await db.activityEvents.count(), rewards: await db.rewardReceipts.count() });
  it('rejects without a persisted pair', async () => {
    const m = await owner();
    expect(await saveConversationCompletion(m, mockUid)).toEqual({ status: 'rejected', reason: 'no-pair' });
    mockTurns.push({ fail: new Error('synthetic failure') }); await m.session!.send('Synthetic failed');
    expect(await saveConversationCompletion(m, mockUid)).toEqual({ status: 'rejected', reason: 'no-pair' });
    expect(await counts()).toEqual({ events: 0, rewards: 0 });
  });
  it('rejects while a reply is pending', async () => {
    let release!: () => void; const m = await owner();
    mockTurns.push({}); await m.session!.send('Synthetic first');
    mockTurns.push({ hold: new Promise<void>(resolve => { release = resolve; }) });
    const sending = m.session!.send('Synthetic second');
    while (mockRequests.length < 2) await new Promise(resolve => setTimeout(resolve, 0));
    expect(await saveConversationCompletion(m, mockUid)).toEqual({ status: 'rejected', reason: 'pending' });
    release(); await sending;
    expect(await counts()).toEqual({ events: 0, rewards: 0 });
  });
  it('an unresolved handoff is ineligible; a handoff resolved earlier is eligible', async () => {
    const m = await owner();
    mockTurns.push({ handoff: HANDOFF }); await m.session!.send('Synthetic first');
    expect(await saveConversationCompletion(m, mockUid)).toEqual({ status: 'rejected', reason: 'unresolved-handoff' });
    m.session!.queueCrisisPath('misunderstanding', HANDOFF);
    mockTurns.push({ handoff: null }); await m.session!.send('Synthetic follow-up');
    const result = await saveConversationCompletion(m, mockUid);
    expect(result).toMatchObject({ status: 'saved', outcome: 'awarded' });
    expect(await counts()).toEqual({ events: 1, rewards: 1 });
    const event = (await db.activityEvents.toArray())[0];
    expect(event).toMatchObject({ source_type: 'conversation', source_id: m.session!.conversationId, owner_uid: mockUid });
  });
  it('a double click saves one event and one piece', async () => {
    const m = await owner(); mockTurns.push({}); await m.session!.send('Synthetic message');
    const results = await Promise.all([saveConversationCompletion(m, mockUid), saveConversationCompletion(m, mockUid)]);
    expect(results.map(r => r.status === 'saved' ? r.outcome : r.reason).sort()).toEqual(['awarded', 'busy']);
    expect(await saveConversationCompletion(m, mockUid)).toMatchObject({ status: 'saved', outcome: 'duplicate' });
    expect(await counts()).toEqual({ events: 1, rewards: 1 });
  });
  it('two tabs completing the same conversation save one event and one piece', async () => {
    const a = await owner(); mockTurns.push({}); await a.session!.send('Synthetic message');
    const b = await owner(); expect(b.session!.conversationId).toBe(a.session!.conversationId);
    const results = await Promise.all([saveConversationCompletion(a, mockUid), saveConversationCompletion(b, mockUid)]);
    expect(results.filter(r => r.status === 'saved').map(r => (r as { outcome: string }).outcome).sort()).toEqual(['awarded', 'duplicate']);
    expect(await counts()).toEqual({ events: 1, rewards: 1 });
  });
  it('a second completion the same Karachi day is event-only; the next day earns a piece', async () => {
    const m = await owner(); mockTurns.push({}); await m.session!.send('Synthetic one');
    expect(await saveConversationCompletion(m, mockUid)).toMatchObject({ status: 'saved', outcome: 'awarded' });
    mockTurns.push({}); await m.session!.send('Synthetic two');
    expect(await saveConversationCompletion(m, mockUid)).toMatchObject({ status: 'saved', outcome: 'daily-cap' });
    expect(await counts()).toEqual({ events: 2, rewards: 1 });
    jest.mocked(Date.now).mockReturnValue(Date.parse('2026-10-19T19:30:00.000Z')); // 00:30 on 20 Oct in Karachi
    mockTurns.push({}); await m.session!.send('Synthetic three');
    expect(await saveConversationCompletion(m, mockUid)).toMatchObject({ status: 'saved', outcome: 'awarded' });
    expect(await counts()).toEqual({ events: 3, rewards: 2 });
  });
  it('binds the completion to the signed-in owner', async () => {
    const m = await owner(); mockTurns.push({}); await m.session!.send('Synthetic message');
    mockUid = 'completion-owner-b';
    expect(await saveConversationCompletion(m, 'completion-owner-a')).toEqual({ status: 'rejected', reason: 'owner-changed' });
    expect(await counts()).toEqual({ events: 0, rewards: 0 });
  });
});

describe('New Chat during an open safety handoff', () => {
  const reasonOf = (promise: Promise<unknown>) => promise.then(() => 'resolved', (error: { reason?: string }) => error?.reason ?? String(error));
  it('is blocked with crisis-open while the handoff is open; resuming the same conversation stays allowed', async () => {
    const m = await owner(), id = m.session!.conversationId;
    mockTurns.push({ handoff: HANDOFF }); await m.session!.send('Synthetic first');
    expect((await settled(m)).hasUnresolvedHandoff).toBe(true);
    const header = await db.conversations.get(mockUid);
    expect(await reasonOf(m.archiveAndStartNew(mockUid))).toBe('crisis-open');
    expect(await reasonOf(m.activateArchived(mockUid, 'another-conversation'))).toBe('crisis-open');
    expect(await m.activateArchived(mockUid, id)).toEqual({ conversationId: id, previousConversationId: id });
    expect(m.session!.conversationId).toBe(id); expect(m.getSnapshot().switching).toBe(false);
    expect(await db.conversationArchive.count()).toBe(0);
    expect((await db.conversations.get(mockUid))!.conversationId).toBe(header!.conversationId);
    // The blocked attempt left the conversation usable.
    mockTurns.push({ handoff: HANDOFF }); await m.session!.send('Synthetic still here');
    expect(m.session!.getSnapshot().messages.filter(x => x.status === 'completed')).toHaveLength(4);
  });
  it('re-reads saved rows, so a stale cached flag cannot bypass the block', async () => {
    const m = await owner(); mockTurns.push({}); await m.session!.send('Synthetic first');
    expect((await settled(m)).hasUnresolvedHandoff).toBe(false);
    const [ai] = await aiRows(); await db.messages.update(ai.id, { handoff_open: true });
    expect(await reasonOf(m.archiveAndStartNew(mockUid))).toBe('crisis-open');
    expect(m.getSnapshot().hasUnresolvedHandoff).toBe(true);
    expect(await db.conversationArchive.count()).toBe(0);
  });
  it('is allowed again after a resolving turn returns no handoff', async () => {
    const m = await owner(), a = m.session!.conversationId;
    mockTurns.push({ handoff: HANDOFF }); await m.session!.send('Synthetic first');
    expect(await reasonOf(m.archiveAndStartNew(mockUid))).toBe('crisis-open');
    m.session!.queueCrisisPath('reached_out', HANDOFF);
    mockTurns.push({ handoff: null }); await m.session!.send('Synthetic resolving turn');
    expect((await settled(m)).hasUnresolvedHandoff).toBe(false);
    const { conversationId: b } = await m.archiveAndStartNew(mockUid);
    expect(b).not.toBe(a); expect(await db.conversationArchive.count()).toBe(1);
  });
});
