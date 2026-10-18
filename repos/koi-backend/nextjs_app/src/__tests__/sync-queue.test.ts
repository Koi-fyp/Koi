/** @jest-environment jsdom */
// Real sync.ts queue (localStorage) with a mocked Firestore SDK; no network.
let mockUid: string | null = 'queue-owner-a';
let mockFirestoreReady = true;
const mockSetDoc = jest.fn();
jest.mock('@/lib/firebase', () => ({
  get firestore() { return mockFirestoreReady ? { app: {} } : null; },
  auth: { get currentUser() { return mockUid ? { uid: mockUid } : null; } },
}));
jest.mock('firebase/firestore', () => ({ doc: (_db: unknown, collection: string, id: string) => `${collection}/${id}`, setDoc: (...args: unknown[]) => mockSetDoc(...args) }));
import { syncQueue } from '@/lib/firestore/sync';
import { MESSAGE_SYNC_FIELDS } from '@/lib/firestore/messageSync';

const CIPHER = 'v1:PBKDF2:c3Nzc3Nzc3Nzc3Nzc3Nzcw==:bm9uY2Vub25jZW5v:Y2lwaGVydGV4dGNpcGhlcnRleHQ=';
const legacy = (owner: string | undefined, id: string, cid = 'conv-1') => ({ collection: `conversations/${cid}/messages`, docId: id, priority: 3, timestamp: 1,
  data: { id, conversationId: cid, sender: 'user', content: CIPHER, timestamp: '2026-10-19T08:00:00.000Z', emotion: 'neutral', synced: false,
    ...(owner ? { ownerUid: owner } : {}), replyTo: 'x', companion_state: { emotion: 'joy', intensity: 1 }, handoff_open: true } });
const stored = () => JSON.parse(localStorage.getItem('koi_sync_queue') || '[]');
beforeEach(() => { localStorage.clear(); mockUid = 'queue-owner-a'; mockFirestoreReady = true; mockSetDoc.mockReset().mockResolvedValue(undefined); });

it('re-paths the signed-in owner\'s legacy root-path items once, with the exact payload and a real timestamp', async () => {
  localStorage.setItem('koi_sync_queue', JSON.stringify([legacy('queue-owner-a', 'm1'), legacy('queue-owner-b', 'm2'), legacy(undefined, 'm3')]));
  await syncQueue.flush();
  expect(mockSetDoc).toHaveBeenCalledTimes(1);
  const [path, data, options] = mockSetDoc.mock.calls[0];
  expect(path).toBe('users/queue-owner-a/conversations/conv-1/messages/m1');
  expect(Object.keys(data).sort()).toEqual([...MESSAGE_SYNC_FIELDS].sort());
  expect(data.timestamp).toBeInstanceOf(Date); expect(data.emotion_confidence).toBe(0); expect(options).toEqual({ merge: true });
  // Other owners' and ownerless items are neither adopted nor sent; they stay queued unchanged.
  expect(stored().map((item: { collection: string; docId: string }) => [item.collection, item.docId])).toEqual([['conversations/conv-1/messages', 'm2'], ['conversations/conv-1/messages', 'm3']]);
  mockSetDoc.mockClear(); await syncQueue.flush(); expect(mockSetDoc).not.toHaveBeenCalled();
});

it('keeps owner isolation: another signed-in UID never re-paths or sends the first owner\'s items', async () => {
  localStorage.setItem('koi_sync_queue', JSON.stringify([legacy('queue-owner-a', 'm1')]));
  mockUid = 'queue-owner-b'; await syncQueue.flush();
  expect(mockSetDoc).not.toHaveBeenCalled(); expect(stored()[0].collection).toBe('conversations/conv-1/messages');
  mockUid = 'queue-owner-a'; await syncQueue.flush();
  expect(mockSetDoc.mock.calls[0][0]).toBe('users/queue-owner-a/conversations/conv-1/messages/m1');
});

it('re-paths while offline and retries failed writes on reconnect without losing items queued meanwhile', async () => {
  mockFirestoreReady = false;
  localStorage.setItem('koi_sync_queue', JSON.stringify([legacy('queue-owner-a', 'm1')]));
  await syncQueue.flush();
  expect(stored()[0].collection).toBe('users/queue-owner-a/conversations/conv-1/messages');
  mockFirestoreReady = true;
  let release!: () => void;
  mockSetDoc.mockImplementationOnce(() => new Promise<void>((_resolve, reject) => { release = () => reject(new Error('offline')); }));
  const flushing = syncQueue.flush();
  mockFirestoreReady = false;
  syncQueue.enqueue({ collection: 'users/queue-owner-a/conversations/conv-1/messages', docId: 'm4', data: { id: 'm4' }, priority: 3 });
  mockFirestoreReady = true;
  release(); await flushing;
  expect(stored().map((item: { docId: string }) => item.docId).sort()).toEqual(['m1', 'm4']);
  window.dispatchEvent(new Event('online'));
  await new Promise(resolve => setTimeout(resolve, 0)); await syncQueue.flush();
  expect(mockSetDoc.mock.calls.map(call => call[0]).sort()).toEqual(expect.arrayContaining(['users/queue-owner-a/conversations/conv-1/messages/m1', 'users/queue-owner-a/conversations/conv-1/messages/m4']));
  expect(stored()).toEqual([]);
});

it('a failed immediate write is queued for the next start or sign-in, and preference writes are untouched', async () => {
  mockSetDoc.mockRejectedValueOnce(new Error('permission-denied'));
  syncQueue.enqueue({ collection: 'users', docId: 'queue-owner-a', data: { public_crypto_metadata: { salt: 'public' } }, priority: 4 });
  await new Promise(resolve => setTimeout(resolve, 0));
  expect(stored()).toHaveLength(1);
  await syncQueue.flush();
  expect(mockSetDoc).toHaveBeenLastCalledWith('users/queue-owner-a', { public_crypto_metadata: { salt: 'public' } }, { merge: true });
  expect(stored()).toEqual([]);
});
