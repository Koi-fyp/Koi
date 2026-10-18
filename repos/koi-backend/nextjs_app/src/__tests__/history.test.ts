jest.mock('dexie', () => jest.requireActual('../../node_modules/dexie/dist/dexie.js'));
import { db, type MessageRecord } from '@/lib/db';
import { readOwnedHistory, searchHistory, HISTORY_MESSAGE_LIMIT, HistoryReadError } from '@/lib/history/readHistory';
const row = (id: string, ownerUid = 'a', conversationId = 'one'): MessageRecord => ({ id, ownerUid, conversationId,
  content: 'v1:PBKDF2:' + id, sender: 'user', emotion: 'neutral', timestamp: new Date('2026-10-18T10:00:00Z'), synced: false });
const read = (owner = 'a', decrypt = async (text: string) => text.slice(10)) => readOwnedHistory(owner, decrypt,
  { signal: new AbortController().signal, isCurrentOwner: () => true });
beforeEach(async () => { await db.messages.clear(); await db.conversations.clear(); });
it('lists two genuine owned conversations without adopting foreign or ownerless rows or writing data', async () => {
  await db.messages.bulkAdd([row('first'), row('second','a','two'),row('foreign','b'),{...row('legacy'),ownerUid:undefined}]);
  const decrypt = jest.fn(async text => text.includes('first') ? 'میری بات' : 'Roman Urdu baat');
  const result = await read('a', decrypt);
  expect(result.conversations).toHaveLength(2); expect(decrypt).toHaveBeenCalledTimes(2);
  expect(searchHistory(result,'baat')).toHaveLength(1); expect(searchHistory(result,'میری')).toHaveLength(1);
  expect(await db.messages.count()).toBe(4); expect(await db.conversations.count()).toBe(0);
  expect(result.conversations.every(c=>c.createdAt===null&&!c.active)).toBe(true);
});
it('marks only the real active header for Continue and survives database reopen', async () => {
  await db.messages.add(row('first'));
  await db.conversations.add({uid:'a',conversationId:'one',createdAt:new Date(),lastActiveAt:new Date(),status:'active',revision:1});
  db.close(); await db.open(); expect((await read()).conversations[0].active).toBe(true);
});
it('has an honest empty state and fails closed on locked/corrupt data', async () => {
  expect((await read()).conversations).toEqual([]); await db.messages.add(row('bad'));
  await expect(read('a',async()=>{throw Error('synthetic decryption failure');})).rejects.toBeInstanceOf(HistoryReadError);
});
it('retains readable rows while reporting corrupt rows without disclosing their bodies', async () => {
  await db.messages.bulkAdd([row('good'),row('bad')]);
  const result=await read('a',async text=>{if(text.includes('bad'))throw Error('corrupt');return 'good';});
  expect(result.unreadable).toBe(1);expect(result.conversations[0].messages).toHaveLength(1);
});
it('rejects late decryption after account change and cancellation', async () => {
  await db.messages.add(row('first'));let current=true;
  await expect(readOwnedHistory('a',async()=>{current=false;return 'never exposed';},
    {signal:new AbortController().signal,isCurrentOwner:()=>current})).rejects.toMatchObject({kind:'owner-changed'});
  const abort=new AbortController();abort.abort();await expect(readOwnedHistory('a',async()=>'',{signal:abort.signal,isCurrentOwner:()=>true})).rejects.toBeDefined();
});
it('bounds decryption/search and flags incomplete history rather than claiming full results', async () => {
  await db.messages.bulkAdd(Array.from({length:HISTORY_MESSAGE_LIMIT+3},(_,i)=>row('id-'+i)));
  const decrypt=jest.fn(async()=> 'test');const result=await read('a',decrypt);
  expect(decrypt).toHaveBeenCalledTimes(HISTORY_MESSAGE_LIMIT);expect(result.truncated).toBe(true);
});
