/** @jest-environment jsdom */
// Opens a real v3 KoiDB (fake-indexeddb), then the app's v4 schema; every existing row must survive unchanged.
import Dexie from 'dexie';
jest.mock('dexie', () => jest.requireActual('../../node_modules/dexie/dist/dexie.js'));
import { db } from '@/lib/db';

const V1 = { users: '++id, uid', messages: 'id, conversationId, synced, timestamp', moodEntries: 'id, userId, synced, timestamp', jigsawProgress: 'uid', syncQueue: '++id, priority, createdAt' };
const V2 = { conversations: 'uid, conversationId, lastActiveAt' };
const V3 = {
  activityEvents: 'id, owner_uid, &[owner_uid+source_type+completion_id], [owner_uid+source_type+day_key], completed_at',
  rewardReceipts: 'id, owner_uid, &[owner_uid+source_type+day_key], &[owner_uid+slot_index]',
  milestoneReceipts: 'id, owner_uid, &[owner_uid+milestone]',
};
const ROWS: Record<string, object[]> = {
  users: [{ id: 1, uid: 'synthetic', companion: 'aisha', onboardingComplete: true }],
  messages: [{ id: 'm1', conversationId: 'c1', sender: 'user', content: 'v1:PBKDF2:existing-ciphertext', timestamp: new Date('2026-10-01T00:00:00Z'), ownerUid: 'synthetic', synced: false },
    { id: 'm-legacy', conversationId: 'c0', sender: 'ai', content: 'v1:PBKDF2:legacy', timestamp: new Date('2026-09-01T00:00:00Z'), synced: true }],
  moodEntries: [{ id: 'mood', userId: 'synthetic', timestamp: new Date('2026-10-01T00:00:00Z') }],
  jigsawProgress: [{ uid: 'synthetic', jigsaw_pieces: 14 }],
  syncQueue: [{ id: 1, collection: 'conversations/c1/messages', docId: 'm1', data: { content: 'v1:PBKDF2:existing-ciphertext' }, priority: 3, createdAt: new Date('2026-10-01T00:00:00Z') }],
  conversations: [{ uid: 'synthetic', conversationId: 'c1', createdAt: new Date('2026-10-01T00:00:00Z'), lastActiveAt: new Date('2026-10-02T00:00:00Z'), status: 'active', revision: 7, encryptedState: 'v1:PBKDF2:unchanged-header' }],
  activityEvents: [{ id: 'e', completion_id: 'e', owner_uid: 'synthetic', source_type: 'check_in', day_key: '2026-10-01', completed_at: '2026-10-01T00:00:00.000Z' }],
  rewardReceipts: [{ id: 'r', owner_uid: 'synthetic', source_type: 'check_in', day_key: '2026-10-01', slot_index: 1 }],
  milestoneReceipts: [{ id: 'z', owner_uid: 'synthetic', milestone: 5 }],
};

it.each([1, 2, 3])('upgrading a v%i database to v4 keeps every existing row and adds an empty archive', async version => {
  db.close(); await Dexie.delete('KoiDB');
  const old = new Dexie('KoiDB');
  old.version(1).stores(V1);
  if (version >= 2) old.version(2).stores(V2);
  if (version >= 3) old.version(3).stores(V3);
  await old.open();
  const present = old.tables.map(table => table.name);
  for (const name of present) await old.table(name).bulkPut(ROWS[name]);
  const before: Record<string, unknown[]> = {};
  for (const name of present) before[name] = await old.table(name).toArray();
  old.close();
  await db.open();
  expect(db.verno).toBe(4);
  expect(await db.conversationArchive.count()).toBe(0);
  for (const name of present) expect(await db.table(name).toArray()).toEqual(before[name]);
  db.close();
});

it('the v4 archive is keyed by owner and conversation and is never part of the sync queue', async () => {
  await Dexie.delete('KoiDB'); await db.open();
  const row = { uid: 'synthetic', conversationId: 'c1', createdAt: new Date(), lastActiveAt: new Date(), status: 'active' as const, revision: 1, encryptedState: 'v1:PBKDF2:x', archivedAt: new Date() };
  await db.conversationArchive.put(row); await db.conversationArchive.put({ ...row, uid: 'other' });
  await db.conversationArchive.put({ ...row, revision: 2 });
  expect(await db.conversationArchive.count()).toBe(2);
  expect((await db.conversationArchive.get(['synthetic', 'c1']))!.revision).toBe(2);
  expect(await db.conversationArchive.where('uid').equals('other').count()).toBe(1);
  expect(await db.syncQueue.count()).toBe(0);
});
