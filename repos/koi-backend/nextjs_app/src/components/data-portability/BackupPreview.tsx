'use client';
import { useEffect, useRef, useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { db } from '@/lib/db';
import { readBackupDraft, previewDraftConflicts, BACKUP_MAX_RECORDS, type DraftRecord } from '@/lib/data-portability/backupDraft';
type Preview = { owner: string; count: number; duplicates: number; conflicts: number; newRecords: number };
export default function BackupPreview() {
  const { user, loading } = useAuth();
  const owner = useRef(user?.uid); owner.current = user?.uid;
  const generation = useRef(0);
  const [preview,setPreview]=useState<Preview|null>(null),[error,setError]=useState<string|null>(null),[busy,setBusy]=useState(false);
  useEffect(()=>{generation.current++;setPreview(null);setError(null);setBusy(false);return()=>{generation.current++;};},[user?.uid]);
  const read=async(file:File)=>{
    if(!user||loading)return;
    const uid=user.uid,lease=++generation.current;
    const current=()=>owner.current===uid&&generation.current===lease;
    setPreview(null);setError(null);setBusy(true);
    try {
      // Public owner binding, not a secret or authentication proof.
      const bytes=await crypto.subtle.digest('SHA-256',new TextEncoder().encode('koi-owner:v1:'+uid));
      const binding=[...new Uint8Array(bytes)].map(n=>n.toString(16).padStart(2,'0')).join('');
      if(!current())return;
      const parsed=await readBackupDraft(file,uid,binding);
      if(!current())return;
      const rows=await db.messages.filter(row=>row.ownerUid===uid).limit(BACKUP_MAX_RECORDS+1).toArray();
      const header=await db.conversations.get(uid);
      if(!current())return;
      if(rows.length>BACKUP_MAX_RECORDS)throw new Error('bounded');
      const records:DraftRecord[]=rows.map(row=>({source:'messages',id:row.id,timestamp:new Date(row.timestamp).toISOString(),ciphertext:row.content}));
      if(header?.encryptedState)records.push({source:'conversations',id:uid,timestamp:new Date(header.lastActiveAt).toISOString(),ciphertext:header.encryptedState});
      const result=previewDraftConflicts(parsed,records);
      if(current())setPreview({owner:uid,count:parsed.draft.records.length,duplicates:result.duplicates,conflicts:result.conflicts,newRecords:result.newRecords});
    } catch {if(current())setError('This backup could not be previewed: unsupported file, owner/schema mismatch, or local storage/size limit. No records were changed.');}
    finally {if(current())setBusy(false);}
  };
  const shown=preview?.owner===user?.uid?preview:null;
  return <section className="neo-card p-5 my-5" aria-label="Read-only encrypted backup preview">
    <h2 className="font-bold text-xl">Read-only backup preview</h2>
    <p className="my-3">Draft JSON format only, up to 2 MiB / {BACKUP_MAX_RECORDS} records. Exact Firebase owner metadata must match. UID equality does not prove that your existing key can decrypt this backup. No keys are generated or exported.</p>
    <label>Choose encrypted backup JSON
      <input className="block w-full min-w-0 max-w-full" type="file" accept=".json,application/json" disabled={!user||loading||busy} onChange={e=>{const file=e.target.files?.[0];if(file)void read(file);e.target.value='';}} />
    </label>
    {busy&&<p role="status">Validating file structure and comparing local IDs…</p>}
    {error&&<p role="alert">{error}</p>}
    {shown&&<div role="status"><p>{shown.count} records · {shown.newRecords} new IDs · {shown.duplicates} duplicates · {shown.conflicts} conflicts.</p>
      <p>Metadata-only preview. Decryption and manifest integrity are NOT VERIFIED. Existing-key validation and joint security approval are required. Nothing was imported.</p></div>}
    <p className="text-sm my-3">Anonymous identity/key loss can make a backup unrestorable. No cross-device or browser-reset recovery is promised. Keep the file private; it contains owner metadata and ciphertext.</p>
    <button type="button" className="neo-btn-ghost" style={{whiteSpace:'normal',maxWidth:'100%',width:'100%'}} disabled>Restore unavailable — joint security approval required</button>
  </section>;
}
