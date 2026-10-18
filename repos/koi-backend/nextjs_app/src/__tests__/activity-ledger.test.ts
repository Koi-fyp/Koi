jest.mock('dexie', () => jest.requireActual('../../node_modules/dexie/dist/dexie.js'));
let mockOwner = 'synthetic-owner';
const mockListeners = new Set<(user: { uid: string } | null) => void>();
jest.mock('@/lib/firebase', () => ({ auth: { get currentUser() { return mockOwner ? { uid: mockOwner } : null; } } }));
jest.mock('firebase/auth', () => ({ onAuthStateChanged: (_auth: unknown, callback: (user: { uid: string } | null) => void) => { mockListeners.add(callback); return () => mockListeners.delete(callback); } }));
import Dexie from 'dexie';
import { db, KoiDatabase } from '@/lib/db';
import { activityLedger, createActivityLedger } from '@/lib/activities/activityLedger';
import { karachiDay, REWARD_POLICY, type CompletionCandidate } from '@/lib/activities/rewardPreview';
const candidate = (id = 'completion-a', completedAt = '2026-10-18T12:00:00.000Z'): CompletionCandidate => ({ ownerUid: mockOwner, completionId: id, source: 'conversation', sourceId: `session-${id}`, completedAt, policyVersion: REWARD_POLICY, evidence: { persisted: true, recordedUnderPolicy: true, explicit: true, persistedExchanges: 1, cancelled: false, crisisInterrupted: false } });
const cipher = `v1:PBKDF2:${btoa('a'.repeat(16))}:${btoa('b'.repeat(12))}:${btoa('c'.repeat(32))}`;
beforeEach(async () => { mockOwner = 'synthetic-owner'; mockListeners.clear(); await db.activityEvents.clear(); await db.rewardReceipts.clear(); await db.milestoneReceipts.clear(); });
afterEach(() => jest.restoreAllMocks());
it.each([
  ['2026-10-18T18:59:59.999Z', '2026-10-18'], ['2026-10-18T19:00:00.000Z', '2026-10-19'],
  ['2026-12-31T19:00:00.000Z', '2027-01-01'], ['2028-02-29T19:00:00.000Z', '2028-03-01'],
])('formats exact Karachi year/month/day: %s', (iso, expected) => expect(karachiDay(iso)).toBe(expected));
it('atomically saves one event and receipt, and replay returns the original without another award', async () => {
  const input = candidate();
  const result = await activityLedger.record(input, null);
  expect(result).toMatchObject({ outcome: 'awarded', reward: { slot_index: 1, day_key: '2026-10-18' } });
  expect(await activityLedger.record({ ...input, completedAt: '2026-10-19T12:00:00.000Z' }, null)).toMatchObject({ outcome: 'duplicate', event: { completed_at: input.completedAt }, reward: { slot_index: 1 } });
  const state = await activityLedger.read(mockOwner); expect(state.events).toHaveLength(1); expect(state.rewards).toHaveLength(1); expect(state.milestones).toEqual([]);
});
it('records additional completed activities while enforcing one source/day and separate source caps', async () => {
  await activityLedger.record(candidate(), null);
  expect((await activityLedger.record(candidate('second'), null)).outcome).toBe('daily-cap');
  const input = { ...candidate('checkin'), source: 'check_in' as const, evidence: { ...candidate().evidence, userInitiated: true, consented: true } };
  expect((await activityLedger.record(input, cipher)).reward?.slot_index).toBe(2);
  expect(await db.activityEvents.count()).toBe(3);
});
it('serializes concurrent submissions across independent database connections', async () => {
  const connection = new KoiDatabase();
  try {
    const second = createActivityLedger(connection);
    const results = await Promise.all([activityLedger.record(candidate(), null), second.record(candidate(), null), second.record(candidate('other-completion'), null)]);
    expect(results.map(result => result.outcome).sort()).toEqual(['awarded', 'daily-cap', 'duplicate']);
    expect(await db.rewardReceipts.count()).toBe(1); expect(await db.activityEvents.count()).toBe(2);
  } finally { connection.close(); }
});
it('keeps exactly 25 slots and five permanent milestones; later eligible events are recorded', async () => {
  for (let index = 0; index < 25; index++) await activityLedger.record(candidate(`c${index}`, new Date(Date.UTC(2026, 0, index + 1)).toISOString()), null);
  expect((await activityLedger.record(candidate('after-full', '2026-03-01T12:00:00.000Z'), null)).outcome).toBe('board-full');
  const state = await activityLedger.read(mockOwner);
  expect(state.events).toHaveLength(26); expect(state.rewards.map(receipt => receipt.slot_index)).toEqual(Array.from({ length: 25 }, (_, index) => index + 1));
  expect(state.milestones.map(receipt => receipt.milestone)).toEqual([5, 10, 15, 20, 25]);
});
it('aborts event and award together on an unexpected reward write failure', async () => {
  jest.spyOn(db.rewardReceipts, 'add').mockRejectedValueOnce(new Error('synthetic write failure'));
  await expect(activityLedger.record(candidate(), null)).rejects.toThrow();
  expect(await db.activityEvents.count()).toBe(0); expect(await db.rewardReceipts.count()).toBe(0);
});
it('aborts the event, reward and milestone together on milestone write failure', async () => {
  for (let index = 0; index < 4; index++) await activityLedger.record(candidate(`c${index}`, new Date(Date.UTC(2026, 0, index + 1)).toISOString()), null);
  jest.spyOn(db.milestoneReceipts, 'add').mockRejectedValueOnce(new Error('synthetic milestone failure'));
  await expect(activityLedger.record(candidate('fifth', '2026-03-01T12:00:00.000Z'), null)).rejects.toThrow();
  expect(await db.activityEvents.count()).toBe(4); expect(await db.rewardReceipts.count()).toBe(4); expect(await db.milestoneReceipts.count()).toBe(0);
});
it('rolls back when authenticated owner changes mid-transaction', async () => {
  const add = db.rewardReceipts.add.bind(db.rewardReceipts);
  jest.spyOn(db.rewardReceipts, 'add').mockImplementationOnce((...args) => Dexie.Promise.resolve(add(...args)).then(result => { mockOwner = 'other-owner'; mockListeners.forEach(listener => listener({ uid: mockOwner })); return result; }));
  await expect(activityLedger.record(candidate(), null)).rejects.toMatchObject({ reason: 'owner-changed' });
  expect(await db.activityEvents.count()).toBe(0); expect(await db.rewardReceipts.count()).toBe(0);
});
it('rejects foreign reads/writes and completion ID collisions without exposing another owner event', async () => {
  const input = candidate(); await activityLedger.record(input, null); mockOwner = 'other-owner';
  await expect(activityLedger.read(input.ownerUid)).rejects.toMatchObject({ reason: 'owner-changed' });
  await expect(activityLedger.record(input, null)).rejects.toMatchObject({ reason: 'owner-changed' });
  expect(await activityLedger.read(mockOwner)).toEqual({ events: [], rewards: [], milestones: [] });
  await expect(activityLedger.record(candidate(), null)).rejects.toMatchObject({ reason: 'identity-conflict' });
  expect(await db.activityEvents.count()).toBe(1);
});
it.each([{ explicit: false }, { persisted: false }, { recordedUnderPolicy: false }, { persistedExchanges: 0 }, { cancelled: true }, { crisisInterrupted: true }])('never saves ineligible conversation: %j', async patch => {
  const input = candidate(); await expect(activityLedger.record({ ...input, evidence: { ...input.evidence, ...patch } }, null)).rejects.toMatchObject({ reason: 'invalid-completion' }); expect(await db.activityEvents.count()).toBe(0);
});
it.each([[4, false], [5, true], [6, true]])('breathing requires measured >=80%%: %i/6', async (cycles, eligible) => {
  const input = { ...candidate(), source: 'breathing' as const, evidence: { ...candidate().evidence, completedCycles: cycles as number, totalCycles: 6, durationMs: 50000, endReason: 'completed' as const, measurement: 'client-measured' as const } };
  if (eligible) expect((await activityLedger.record(input, null)).outcome).toBe('awarded');
  else await expect(activityLedger.record(input, null)).rejects.toMatchObject({ reason: 'invalid-completion' });
});
it('requires encrypted check-in payload; rejects plaintext before starting writes', async () => {
  const input = { ...candidate(), source: 'check_in' as const, evidence: { ...candidate().evidence, userInitiated: true, consented: true } };
  for (const payload of [null, 'plaintext']) await expect(activityLedger.record(input, payload)).rejects.toMatchObject({ reason: 'invalid-payload' });
  expect(await db.activityEvents.count()).toBe(0);
});
it('upgrades v2 additively and preserves every old store without generating rewards', async () => {
  db.close(); await db.delete();
  const old = new Dexie('KoiDB');
  old.version(1).stores({ users: '++id, uid', messages: 'id, conversationId, synced, timestamp', moodEntries: 'id, userId, synced, timestamp', jigsawProgress: 'uid', syncQueue: '++id, priority, createdAt' });
  old.version(2).stores({ conversations: 'uid, conversationId, lastActiveAt' });
  await old.open();
  const fixtures = { users: { uid: 'legacy', avatar: 'fox' }, messages: { id: 'm', conversationId: 'c', content: 'synthetic ciphertext' }, conversations: { uid: 'legacy', conversationId: 'c' }, moodEntries: { id: 'mood', userId: 'legacy', mood_rating: 3 }, jigsawProgress: { uid: 'legacy', jigsaw_pieces: 14 }, syncQueue: { collection: 'synthetic', docId: 'q', priority: 4 } };
  for (const [table, row] of Object.entries(fixtures)) await old.table(table).add(row);
  const before = await Promise.all(Object.keys(fixtures).map(table => old.table(table).toArray())); old.close();
  await db.open();
  expect(await Promise.all(Object.keys(fixtures).map(table => db.table(table).toArray()))).toEqual(before);
  expect(await db.activityEvents.count()).toBe(0); expect(await db.rewardReceipts.count()).toBe(0); expect(await db.milestoneReceipts.count()).toBe(0);
  expect(db.rewardReceipts.schema.indexes.find(index => index.name === '[owner_uid+slot_index]')?.unique).toBe(true);
});

it('enforces independent caps for all three sources and opens a new exact Karachi day',async()=>{
 const base=candidate('before-midnight','2026-10-18T18:59:59.999Z');await activityLedger.record(base,null);
 const checkin={...candidate('checkin-independent',base.completedAt),source:'check_in' as const,evidence:{...base.evidence,userInitiated:true,consented:true}};
 await activityLedger.record(checkin,cipher);
 const breathing={...candidate('breathing-independent',base.completedAt),source:'breathing' as const,evidence:{...base.evidence,completedCycles:5,totalCycles:6,durationMs:50000,endReason:'completed' as const,measurement:'client-measured' as const}};
 await activityLedger.record(breathing,null);expect(await db.rewardReceipts.count()).toBe(3);
 expect((await activityLedger.record(candidate('after-midnight','2026-10-18T19:00:00.000Z'),null)).reward?.slot_index).toBe(4);
});
it('reopening the database never reissues a completion and unique slot conflicts roll back',async()=>{
 const input=candidate();await activityLedger.record(input,null);db.close();await db.open();expect((await activityLedger.record(input,null)).outcome).toBe('duplicate');
 const add=db.rewardReceipts.add.bind(db.rewardReceipts);
 jest.spyOn(db.rewardReceipts,'add').mockImplementationOnce(receipt=>add({...receipt,slot_index:1}));
 await expect(activityLedger.record(candidate('conflict','2026-10-19T12:00:00.000Z'),null)).rejects.toThrow();
 expect(await db.activityEvents.count()).toBe(1);expect(await db.rewardReceipts.count()).toBe(1);
});
it.each([47999,0,NaN])('rejects inadequate breathing duration before writes: %s',async durationMs=>{
 const input={...candidate(),source:'breathing' as const,evidence:{...candidate().evidence,completedCycles:5,totalCycles:6,durationMs,endReason:'completed' as const,measurement:'client-measured' as const}};
 await expect(activityLedger.record(input,null)).rejects.toMatchObject({reason:'invalid-completion'});expect(await db.activityEvents.count()).toBe(0);
});

it('rolls back even when the activity insert succeeds before an unexpected failure',async()=>{
 const add=db.activityEvents.add.bind(db.activityEvents);
 jest.spyOn(db.activityEvents,'add').mockImplementationOnce(event=>Dexie.Promise.resolve(add(event)).then(()=>{throw new Error('synthetic failure immediately after event insertion');}));
 await expect(activityLedger.record(candidate(),null)).rejects.toThrow();expect(await db.activityEvents.count()).toBe(0);expect(await db.rewardReceipts.count()).toBe(0);expect(await db.milestoneReceipts.count()).toBe(0);
});
it('deduplicates a measured breathing completion and never modifies legacy progress',async()=>{
 const legacy={uid:mockOwner,jigsaw_pieces:14,pieces_by_source:{conversations:14,check_ins:0,breathing:0,tasks:0,bonuses:0},milestones_reached:[1],last_updated:new Date('2026-01-01T00:00:00Z')};await db.jigsawProgress.put(legacy);
 const input={...candidate('breathing-stable'),source:'breathing' as const,evidence:{...candidate().evidence,completedCycles:6,totalCycles:6,durationMs:60000,endReason:'completed' as const,measurement:'client-measured' as const}};
 expect((await activityLedger.record(input,null)).outcome).toBe('awarded');expect((await activityLedger.record(input,null)).outcome).toBe('duplicate');
 expect(await db.activityEvents.count()).toBe(1);expect(await db.rewardReceipts.count()).toBe(1);expect(await db.jigsawProgress.get(mockOwner)).toEqual(legacy);
});
