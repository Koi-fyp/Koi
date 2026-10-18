import { TextEncoder } from 'util';
import { BackupValidationError, parseBackupDraft, readBackupDraft, BACKUP_MAX_BYTES } from '@/lib/data-portability/backupDraft';
beforeAll(()=>{Object.assign(globalThis,{TextEncoder});});
const binding='a'.repeat(64);
const draft={kind:'koi-backup-draft',schemaVersion:1,ownerUid:'synthetic-owner',ownerBinding:binding,createdAt:'2026-10-18T10:00:00.000Z',compatibility:'same-owner-existing-key-only',sources:[],counts:{messages:0,conversations:0},records:[]};
it.each([['file.txt','text/plain'],['file.csv','text/csv'],['file.pdf','application/pdf'],['file.docx','application/octet-stream'],['file.json','text/html']])('rejects unsupported file %s before reading',async(name,type)=>{
  const text=jest.fn(async()=>JSON.stringify(draft));
  await expect(readBackupDraft({name,type,size:50,text},'synthetic-owner',binding)).rejects.toMatchObject({code:'file-type'});expect(text).not.toHaveBeenCalled();
});
it.each([0,BACKUP_MAX_BYTES+1])('explains size limits before reading %i bytes',async size=>{
  await expect(readBackupDraft({name:'file.json',type:'',size,text:async()=>''},'synthetic-owner',binding)).rejects.toMatchObject({code:'size'});
});
it.each([['{','json'],['{}','schema'],[JSON.stringify({...draft,schemaVersion:99}),'version'],[JSON.stringify({...draft,ownerUid:'other'}),'owner']])('distinguishes malformed/arbitrary/version/owner validation failures', (text,code)=>{
  try{parseBackupDraft(text,'synthetic-owner',binding);throw Error('expected rejection');}catch(error){expect(error).toBeInstanceOf(BackupValidationError);expect(error).toMatchObject({code});}
});
it('explains malformed ciphertext instead of calling metadata verification restoration',()=>{
  expect(()=>parseBackupDraft(JSON.stringify({...draft,sources:['messages'],counts:{messages:1,conversations:0},records:[{source:'messages',id:'one',timestamp:draft.createdAt,ciphertext:'plain'}]}),'synthetic-owner',binding)).toThrow('malformed encrypted content');
});
