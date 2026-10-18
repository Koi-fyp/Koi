/** @jest-environment node */
// Real conversationService + real AES-GCM encrypt; transport is a synthetic fixture.
import type { ChatServerEvent } from '@/lib/conversation/chatContract';
const mockUid = 'sync-owner-a';
jest.mock('dexie', () => jest.requireActual('../../node_modules/dexie/dist/dexie.js'));
jest.mock('@/lib/firebase', () => ({ firestore: null, auth: { get currentUser() { return { uid: mockUid, isAnonymous: true, providerData: [], getIdToken: async () => 'synthetic-token' }; } } }));
jest.mock('@/lib/firestore/sync', () => ({ syncQueue: { enqueue: jest.fn() } }));
jest.mock('@/lib/crypto', () => ({ ...jest.requireActual('@/lib/crypto'),
  getActiveCryptoContext: async () => ({ secret: 'synthetic-device-secret', saltB64: Buffer.from('s'.repeat(16)).toString('base64') }) }));
jest.mock('@/lib/conversation/jsonChatTransport', () => ({
  chatEndpoint: () => 'https://koi.example.test/chat',
  postJsonChat: async (request: { audio?: Blob }, options: { onEvent: (event: ChatServerEvent) => void }) => {
    if (request.audio) options.onEvent({ event: 'transcript', data: { text: 'Synthetic spoken words' } });
    options.onEvent({ event: 'handoff', data: { to: 'crisis', reason: 'synthetic' } });
    options.onEvent({ event: 'done', data: { full_text: 'Synthetic reply text', companion_state: { emotion: 'sorrow', intensity: 0.4 }, handoff: { to: 'crisis', reason: 'synthetic' } } });
    return { reply: 'Synthetic reply text', companion_state: { emotion: 'sorrow', intensity: 0.4 }, latency_ms: 1 };
  },
}));
import { db } from '@/lib/db';
import { syncQueue } from '@/lib/firestore/sync';
import { sendMessage } from '@/lib/conversation/conversationService';
import { MESSAGE_SYNC_FIELDS } from '@/lib/firestore/messageSync';

// Exact patterns from E:\Koi\Koi-App\rules_draft\firestore.rules.phase1 (isCiphertext / messageOk).
const RULE_CIPHERTEXT = /^v1:PBKDF2:[A-Za-z0-9+/]{22}==:[A-Za-z0-9+/]{16}:[A-Za-z0-9+/]{22,}={0,2}$/;
const options = (n: number) => ({ signal: new AbortController().signal, userMessageId: `user-${n}`, assistantMessageId: `assistant-${n}` });
beforeEach(async () => { jest.mocked(syncQueue.enqueue).mockClear(); for (const table of db.tables) await table.clear(); });

it('queues users/{uid}/conversations/{cid}/messages/{mid} with exactly the eight rule fields and ciphertext only', async () => {
  await sendMessage(mockUid, 'conversation-a', 'Synthetic private words', [], { isLinked: false }, options(1));
  const items = jest.mocked(syncQueue.enqueue).mock.calls.map(([item]) => item);
  expect(items.map(item => [item.collection, item.docId])).toEqual([
    [`users/${mockUid}/conversations/conversation-a/messages`, 'user-1'],
    [`users/${mockUid}/conversations/conversation-a/messages`, 'assistant-1'],
  ]);
  for (const { data, docId } of items) {
    expect(Object.keys(data).sort()).toEqual([...MESSAGE_SYNC_FIELDS].sort());
    expect(data).toMatchObject({ id: docId, conversationId: 'conversation-a', synced: false });
    expect(['user', 'ai']).toContain(data.sender);
    expect(data.content).toMatch(RULE_CIPHERTEXT); expect((data.content as string).length).toBeLessThanOrEqual(65536);
    expect(data.timestamp).toBeInstanceOf(Date);
    expect(typeof data.emotion).toBe('string'); expect((data.emotion as string).length).toBeLessThanOrEqual(32);
    expect(data.emotion_confidence).toBeGreaterThanOrEqual(0); expect(data.emotion_confidence).toBeLessThanOrEqual(1);
    expect(JSON.stringify(data)).not.toMatch(/Synthetic|handoff|done_seen|ownerUid|replyTo|companion_state|audio/);
  }
  // Local evidence is kept on the device row only.
  expect(await db.messages.get('assistant-1')).toMatchObject({ handoff_open: true, done_seen: true, replyTo: 'user-1', ownerUid: mockUid });
});

it('a voice turn queues the transcript ciphertext, never audio', async () => {
  await sendMessage(mockUid, 'conversation-v', '', [], { isLinked: false }, options(2), { audio: new Blob([new Uint8Array(32)], { type: 'audio/webm' }) });
  const items = jest.mocked(syncQueue.enqueue).mock.calls.map(([item]) => item);
  expect(items).toHaveLength(2);
  for (const { data } of items) { expect(Object.keys(data).sort()).toEqual([...MESSAGE_SYNC_FIELDS].sort()); expect(JSON.stringify(data)).not.toMatch(/Synthetic|audio|Blob/); }
});
