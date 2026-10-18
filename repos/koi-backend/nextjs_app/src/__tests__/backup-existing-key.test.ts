import { webcrypto } from 'crypto';
import { TextEncoder, TextDecoder } from 'util';
jest.mock('@/lib/firebase',()=>({firestore:null}));
jest.mock('@/lib/firestore/sync',()=>({syncQueue:{enqueue:jest.fn()}}));
import { encrypt, decrypt } from '@/lib/crypto';
import { parseBackupDraft, verifyDraftCiphertexts } from '@/lib/data-portability/backupDraft';
beforeAll(()=>{Object.defineProperty(globalThis,'crypto',{configurable:true,value:webcrypto});Object.assign(globalThis,{TextEncoder,TextDecoder});});
it('verifies genuine existing-crypto ciphertext, rejects wrong/missing keys and never authorizes restore',async()=>{
  const payload=await encrypt('Synthetic backup record','fixture-key-only',btoa('s'.repeat(16)));
  const parsed=parseBackupDraft(JSON.stringify({kind:'koi-backup-draft',schemaVersion:1,ownerUid:'fixture-owner',ownerBinding:'a'.repeat(64),
    compatibility:'same-owner-existing-key-only',createdAt:'2026-10-18T10:00:00.000Z',sources:['messages'],counts:{messages:1,conversations:0},
    records:[{id:'one',source:'messages',timestamp:'2026-10-18T10:00:00.000Z',ciphertext:payload}]}),'fixture-owner','a'.repeat(64));
  const access={currentOwner:()=> 'fixture-owner',signal:new AbortController().signal};
  expect(await verifyDraftCiphertexts(parsed,access)).toMatchObject({reason:'existing-key-unavailable',importAllowed:false});
  expect(await verifyDraftCiphertexts(parsed,{...access,decryptExisting:text=>decrypt(text,'wrong-fixture-key')})).toMatchObject({status:'blocked'});
  expect(await verifyDraftCiphertexts(parsed,{...access,decryptExisting:text=>decrypt(text,'fixture-key-only')})).toMatchObject({status:'ciphertexts-verified',manifestIntegrity:'NOT VERIFIED',importAllowed:false});
  const parts=payload.split(':');const bytes=atob(parts[4]);parts[4]=btoa(String.fromCharCode(bytes.charCodeAt(0)^1)+bytes.slice(1));
  const tampered={...parsed,draft:{...parsed.draft,records:[{...parsed.draft.records[0],ciphertext:parts.join(':')}]}};
  expect(await verifyDraftCiphertexts(tampered,{...access,decryptExisting:text=>decrypt(text,'fixture-key-only')})).toMatchObject({reason:'ciphertext-could-not-be-authenticated',importAllowed:false});
  let owner='fixture-owner';
  expect(await verifyDraftCiphertexts(parsed,{...access,currentOwner:()=>owner,decryptExisting:async text=>{const plain=await decrypt(text,'fixture-key-only');owner='another-fixture-owner';return plain;}})).toMatchObject({reason:'owner-changed-or-cancelled'});
});
