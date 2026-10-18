import React from 'react';
import { render,screen,fireEvent } from '@testing-library/react';
import {webcrypto} from 'crypto';
import {TextEncoder} from 'util';
jest.mock('dexie',()=>jest.requireActual('../../node_modules/dexie/dist/dexie.js'));
jest.mock('@/contexts/AuthContext',()=>({useAuth:()=>({user:{uid:'fixture-owner'},loading:false})}));
import Preview from '@/components/data-portability/BackupPreview';
import {db} from '@/lib/db';
beforeAll(()=>{Object.defineProperty(globalThis,'crypto',{configurable:true,value:webcrypto});Object.assign(globalThis,{TextEncoder});});
beforeEach(async()=>{await db.messages.clear();await db.conversations.clear();});
it('shows a real bounded structural preview without enabling or writing restoration',async()=>{
  const digest=await webcrypto.subtle.digest('SHA-256',new TextEncoder().encode('koi-owner:v1:fixture-owner'));
  const binding=[...new Uint8Array(digest)].map(n=>n.toString(16).padStart(2,'0')).join('');
  const text=JSON.stringify({kind:'koi-backup-draft',schemaVersion:1,ownerUid:'fixture-owner',ownerBinding:binding,compatibility:'same-owner-existing-key-only',
    createdAt:'2026-10-18T10:00:00.000Z',sources:[],counts:{messages:0,conversations:0},records:[]});
  render(<Preview />);fireEvent.change(screen.getByLabelText('Choose encrypted backup JSON'),{target:{files:[{name:'fixture.json',size:text.length,type:'application/json',text:async()=>text}]}});
  await screen.findByText(/Metadata-only preview/);expect(screen.getByRole('button',{name:/Restore unavailable/})).toBeDisabled();
  expect(await db.messages.count()).toBe(0);expect(await db.conversations.count()).toBe(0);
});
it('rejects an invalid file and never reports import success',async()=>{
  render(<Preview />);fireEvent.change(screen.getByLabelText('Choose encrypted backup JSON'),{target:{files:[{name:'fixture.json',size:2,type:'application/json',text:async()=>'{}'}]}});
  await screen.findByRole('alert');expect(screen.queryByText(/Nothing was imported/)).toBeNull();
});
