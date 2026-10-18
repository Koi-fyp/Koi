import { TextEncoder } from 'util';
jest.mock('dexie',()=>jest.requireActual('../../node_modules/dexie/dist/dexie.js'));
import { db, type MessageRecord } from '@/lib/db';
import { readCiphertextExport, DATA_EXPORT_MAX_RECORDS, serializeCiphertextExport } from '@/lib/data-portability/ciphertextExport';
beforeAll(()=>{Object.assign(globalThis,{TextEncoder});});
const at=new Date('2026-10-18T10:00:00.000Z');
const cipher='v1:PBKDF2:'+btoa('s'.repeat(16))+':'+btoa('n'.repeat(12))+':'+btoa('c'.repeat(32));
const message=(id:string,ownerUid:string|undefined='owner-a'):MessageRecord=>({id,ownerUid,conversationId:'thread-a',sender:'user',content:cipher,timestamp:at,emotion:'neutral',synced:false});
const access=(currentOwner=()=> 'owner-a')=>({currentOwner,signal:new AbortController().signal});
beforeEach(async()=>{await db.messages.clear();await db.conversations.clear();});
it('exports only exact-owner ciphertext and allowlisted metadata in one read-only transaction, without keys or writes',async()=>{
  await db.messages.bulkPut([{...message('one'),crisis_flag:true,sentiment_score:0.9,...{unexpected:'synthetic nonexportable metadata'}},message('foreign','owner-b'),message('legacy',undefined)]);
  // Explicit ownerless row, distinct from the helper default.
  await db.messages.update('legacy',{ownerUid:undefined});
  await db.conversations.put({uid:'owner-a',conversationId:'thread-a',createdAt:at,lastActiveAt:at,status:'active',revision:2,encryptedState:cipher});
  const before=await db.messages.toArray(),headers=await db.conversations.toArray();
  const transaction=jest.spyOn(db,'transaction');
  const value=await readCiphertextExport('owner-a',access());
  expect(transaction.mock.calls).toHaveLength(1);expect(transaction.mock.calls[0][0]).toBe('r');transaction.mockRestore();
  expect(value.counts).toEqual({messages:1,conversationSnapshots:1});expect(value.messages[0].ciphertext).toBe(cipher);
  expect(value).toMatchObject({restorationSupported:false,decryptionVerified:false,manifestAuthenticated:false,originalKeyRequiredToDecrypt:true});
  const text=JSON.stringify(value);expect(text).not.toMatch(/foreign|legacy|sentiment_score|crisis_flag|unexpected|secret|token|password/);
  expect(await db.messages.toArray()).toEqual(before);expect(await db.conversations.toArray()).toEqual(headers);
});
it('copies encrypted records without any existing key, but never marks content decryptable/restorable',async()=>{
  await db.messages.add(message('one'));const value=await readCiphertextExport('owner-a',access());
  expect(value.messages).toHaveLength(1);expect(value.decryptionVerified).toBe(false);expect(value.restorationSupported).toBe(false);
});
it('rejects foreign identity before reading and late account change after reading',async()=>{
  await db.messages.add(message('one'));
  await expect(readCiphertextExport('owner-a',access(()=> 'owner-b'))).rejects.toMatchObject({reason:'owner-changed'});
  let calls=0;await expect(readCiphertextExport('owner-a',access(()=>++calls===1?'owner-a':'owner-b'))).rejects.toMatchObject({reason:'owner-changed'});
});
it('rejects aborts, empty records, malformed owned ciphertext and missing snapshots without partial files',async()=>{
  const controller=new AbortController();controller.abort();await expect(readCiphertextExport('owner-a',{...access(),signal:controller.signal})).rejects.toMatchObject({reason:'cancelled'});
  await expect(readCiphertextExport('owner-a',access())).rejects.toMatchObject({reason:'empty'});
  await db.messages.add({...message('bad'),content:'plain synthetic text'});await expect(readCiphertextExport('owner-a',access())).rejects.toMatchObject({reason:'invalid-record'});
  await db.messages.clear();await db.conversations.add({uid:'owner-a',conversationId:'thread-a',createdAt:at,lastActiveAt:at,status:'active',revision:0});
  await expect(readCiphertextExport('owner-a',access())).rejects.toMatchObject({reason:'snapshot-unavailable'});
});
it('rejects too many records instead of silently truncating',async()=>{
  await db.messages.bulkPut(Array.from({length:DATA_EXPORT_MAX_RECORDS+1},(_,i)=>message(String(i))));
  await expect(readCiphertextExport('owner-a',access())).rejects.toMatchObject({reason:'limit'});
});
it('rejects an oversized serialized file without truncating ciphertext',async()=>{
  await db.messages.add(message('one'));const value=await readCiphertextExport('owner-a',access());
  const oversized={...value,messages:[{...value.messages[0],ciphertext:'x'.repeat(2*1024*1024)}]};
  expect(()=>serializeCiphertextExport(oversized)).toThrow('No partial file');
});
it('preserves reply relationships and does not label structurally valid altered ciphertext authenticated',async()=>{
  await db.messages.bulkPut([message('user'),{...message('reply'),sender:'ai',replyTo:'user',content:cipher.slice(0,-4)+'AAAA'}]);
  const value=await readCiphertextExport('owner-a',access());
  expect(value.messages.find(m=>m.id==='reply')?.replyTo).toBe('user');expect(value.manifestAuthenticated).toBe(false);expect(value.decryptionVerified).toBe(false);
});
