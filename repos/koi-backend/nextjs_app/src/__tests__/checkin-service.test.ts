import { webcrypto } from 'crypto';
import { TextEncoder, TextDecoder } from 'util';
jest.mock('dexie', () => jest.requireActual('../../node_modules/dexie/dist/dexie.js'));
let mockUid = 'synthetic-checkin-owner', mockAnonymous = true;
jest.mock('@/lib/firebase', () => ({ auth: { get currentUser() { return { uid: mockUid, isAnonymous: mockAnonymous }; } }, firestore: null }));
jest.mock('firebase/auth', () => ({ onAuthStateChanged: () => () => {} }));
jest.mock('@/lib/firestore/sync', () => ({ syncQueue: { enqueue: jest.fn() } }));
import { db } from '@/lib/db';
import { saveCheckIn, readCheckIns, checkInAvailable, CHECK_IN_SCALE } from '@/lib/checkins/checkInService';
import { decrypt } from '@/lib/crypto';
import { syncQueue } from '@/lib/firestore/sync';
const draft = () => ({ ownerUid: mockUid, entryId: 'check-in-synthetic-stable-id', occurredAt: '2026-10-18T12:00:00.000Z', consent: true, ratings: { mood: 2, connection: 3, energy: 4 } });
beforeAll(() => { Object.defineProperty(globalThis, 'crypto', { configurable: true, value: webcrypto }); Object.assign(globalThis, { TextEncoder, TextDecoder }); });
beforeEach(async () => {
  mockUid = 'synthetic-checkin-owner'; mockAnonymous = true; localStorage.clear();
  jest.spyOn(Date, 'now').mockReturnValue(Date.parse('2026-10-18T12:00:00.000Z'));
  localStorage.setItem('koi_anon_secret', 'synthetic-existing-secret-not-exported'); localStorage.setItem(`koi_salt_cache_${mockUid}`, btoa('s'.repeat(16)));
  await db.activityEvents.clear(); await db.rewardReceipts.clear(); await db.milestoneReceipts.clear(); jest.clearAllMocks();
});
afterEach(() => jest.restoreAllMocks());
it('saves genuine AES-GCM ratings, decrypts with the existing key, retains UUID and never syncs', async () => {
  const input = draft(); const result = await saveCheckIn(input);
  expect(result.outcome).toBe('awarded');
  const row = await db.activityEvents.get(input.entryId);
  expect(row!.payload).toMatch(/^v1:PBKDF2:/);
  expect(JSON.parse(await decrypt(row!.payload!, 'synthetic-existing-secret-not-exported'))).toEqual({ scale_version: CHECK_IN_SCALE.version, ...input.ratings });
  const metadata = { ...row }; delete metadata.payload;
  expect(JSON.stringify(metadata)).not.toMatch(/"(?:mood|connection|energy)"/);
  expect(JSON.stringify(await db.rewardReceipts.toArray())).not.toMatch(/"(?:mood|connection|energy)"/);
  expect([...Array(localStorage.length)].map((_, i) => localStorage.getItem(localStorage.key(i)!)).join(' ')).not.toContain('scale_version');
  expect((await readCheckIns(mockUid)).entries).toEqual([{ id: input.entryId, completedAt: input.occurredAt, ...input.ratings }]);
  expect((await saveCheckIn(input)).outcome).toBe('duplicate'); expect(await db.activityEvents.count()).toBe(1);
  expect(syncQueue.enqueue).not.toHaveBeenCalled();
});
it.each([{ consent: false }, { ratings: { mood: 0, connection: 3, energy: 4 } }, { ratings: { mood: 6, connection: 3, energy: 4 } }, { ratings: { mood: 2.5, connection: 3, energy: 4 } }, { ratings: { mood: undefined, connection: 3, energy: 4 } }])('rejects invalid/unconsented input before writing: %j', async patch => {
  await expect(saveCheckIn({ ...draft(), ...patch } as ReturnType<typeof draft>)).rejects.toThrow(); expect(await db.activityEvents.count()).toBe(0); expect(await db.rewardReceipts.count()).toBe(0);
});
it.each(['key', 'salt', 'linked'])('stays locked without existing context, never regenerates key/salt: %s', async missing => {
  if (missing === 'key') localStorage.removeItem('koi_anon_secret'); else if (missing === 'salt') localStorage.removeItem(`koi_salt_cache_${mockUid}`); else mockAnonymous = false;
  const before = { ...localStorage }; await expect(checkInAvailable(mockUid)).rejects.toMatchObject({ reason: 'locked' }); await expect(saveCheckIn(draft())).rejects.toMatchObject({ reason: 'locked' });
  expect({ ...localStorage }).toEqual(before); expect(await db.activityEvents.count()).toBe(0);
});
it('saves a second same-day check-in but never another daily piece', async () => {
  await saveCheckIn(draft()); const second = await saveCheckIn({ ...draft(), entryId: 'second-check-in' });
  expect(second.outcome).toBe('daily-cap'); expect(await db.activityEvents.count()).toBe(2); expect(await db.rewardReceipts.count()).toBe(1);
});
it('rejects foreign owners and leaves corrupt ciphertext unreadable without adopting/deleting it', async () => {
  await expect(saveCheckIn({ ...draft(), ownerUid: 'other-owner' })).rejects.toMatchObject({ reason: 'owner-changed' });
  const result = await saveCheckIn(draft()); const parts = result.event.payload!.split(':'); parts[4] = btoa('x'.repeat(32));
  await db.activityEvents.update(result.event.id, { payload: parts.join(':') });
  expect(await readCheckIns(mockUid)).toEqual({ entries: [], unreadable: 1 }); expect(await db.activityEvents.count()).toBe(1);
  mockUid = 'other-owner'; expect(await readCheckIns(mockUid)).toEqual({ entries: [], unreadable: 0 });
});

it('uses the actual save day after encryption, not an old form timestamp, and retry retains the persisted event',async()=>{
 jest.spyOn(Date,'now').mockReturnValue(Date.parse('2026-10-18T19:00:00.000Z'));
 const saved=await saveCheckIn({...draft(),occurredAt:'2026-10-17T12:00:00.000Z'});
 expect(saved.event.day_key).toBe('2026-10-19');expect(saved.event.completed_at).toBe('2026-10-18T19:00:00.000Z');
 jest.spyOn(Date,'now').mockReturnValue(Date.parse('2026-10-19T19:00:00.000Z'));
 const retry=await saveCheckIn(draft());expect(retry.outcome).toBe('duplicate');expect(retry.event.day_key).toBe('2026-10-19');expect(await db.rewardReceipts.count()).toBe(1);
});

it('account switching while an encrypted save is starting cannot persist under either new owner or stale owner',async()=>{
 const saving=saveCheckIn(draft());mockUid='new-owner-during-save';
 await expect(saving).rejects.toMatchObject({reason:'owner-changed'});
 expect(await db.activityEvents.count()).toBe(0);expect(await db.rewardReceipts.count()).toBe(0);
});
