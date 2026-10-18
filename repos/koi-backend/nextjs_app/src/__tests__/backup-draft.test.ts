import { TextEncoder } from 'util';
import { BACKUP_MAX_BYTES, BACKUP_MAX_RECORDS, parseBackupDraft, readBackupDraft, previewDraftConflicts } from '@/lib/data-portability/backupDraft';
beforeAll(() => { Object.assign(globalThis, { TextEncoder }); });
const owner = 'a'.repeat(64);
const cipher = 'v1:PBKDF2:' + btoa('s'.repeat(16)) + ':' + btoa('n'.repeat(12)) + ':' + btoa('c'.repeat(32));
const record = { source:'messages',id:'fixture-one',timestamp:'2026-10-18T10:00:00.000Z',ciphertext:cipher };
const draft = () => ({kind:'koi-backup-draft',schemaVersion:1,ownerUid:'fixture-owner',ownerBinding:owner,compatibility:'same-owner-existing-key-only',createdAt:record.timestamp,sources:['messages'],counts:{messages:1,conversations:0},records:[record]});
it('returns only a structure preview, never proof of owner/key/integrity or permission to import', () => {
  const value=parseBackupDraft(JSON.stringify(draft()),'fixture-owner',owner);
  expect(value).toMatchObject({integrity:'NOT VERIFIED',decryption:'NOT VERIFIED',importAllowed:false});
  expect(previewDraftConflicts(value,[])).toMatchObject({newRecords:1,conflicts:0,duplicates:0,importAllowed:false});
});
it.each(['', '{}', '{', '[]'])('rejects empty, invalid and unsupported envelopes without a writer: %s', text => {
  expect(()=>parseBackupDraft(text,'fixture-owner',owner)).toThrow('No records were changed');
});
it.each([
  {schemaVersion:0},{ownerUid:'another-owner'},{ownerBinding:'b'.repeat(64)},{counts:{messages:42,conversations:0}},
  {records:[record,record]}, {records:[{...record,ciphertext:'plaintext'}]},
  {token:'must-never-be-accepted'}, {createdAt:'2026-02-31T00:00:00.000Z'},
  {records:Array.from({length:BACKUP_MAX_RECORDS+1},(_,i)=>({...record,id:String(i)}))},
])('rejects owner/schema/count/type/duplicate/unsupported-field/record-limit changes', patch => {
  expect(()=>parseBackupDraft(JSON.stringify({...draft(),...patch}),'fixture-owner',owner)).toThrow();
});
it('does not pretend a structurally valid altered ciphertext is authenticated', () => {
  const altered={...record,ciphertext:cipher.slice(0,-4)+'AAAA'};
  expect(parseBackupDraft(JSON.stringify({...draft(),records:[altered]}),'fixture-owner',owner).integrity).toBe('NOT VERIFIED');
});
it('classifies stable-ID replay as duplicate and different ciphertext as conflict, never overwriting', () => {
  const parsed=parseBackupDraft(JSON.stringify(draft()),'fixture-owner',owner);const existing=[{...record,source:'messages' as const}];
  expect(previewDraftConflicts(parsed,existing)).toMatchObject({duplicates:1,newRecords:0,conflicts:0});
  expect(previewDraftConflicts(parsed,[{...existing[0],ciphertext:'different'}])).toMatchObject({conflicts:1,duplicates:0});
  expect(existing[0].ciphertext).toBe(cipher);
});
it('rejects oversized/zero-byte/disallowed files before reading and interrupted reads without writes', async () => {
  const text=jest.fn(async()=>JSON.stringify(draft()));
  for(const patch of [{size:0},{size:BACKUP_MAX_BYTES+1},{name:'file.pdf'},{type:'text/html'}]) {
    await expect(readBackupDraft({name:'file.json',size:1,type:'application/json',text,...patch},'fixture-owner',owner)).rejects.toThrow();
  }
  expect(text).not.toHaveBeenCalled();
  await expect(readBackupDraft({name:'file.json',size:1,type:'application/json',text:async()=>{throw Error('interrupted');}},'fixture-owner',owner)).rejects.toThrow();
});
