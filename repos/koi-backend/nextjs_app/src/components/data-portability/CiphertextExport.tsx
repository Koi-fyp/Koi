'use client';
import { useEffect, useRef, useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { useSharedConversation } from '@/contexts/ConversationContext';
import { auth } from '@/lib/firebase';
import { assertExportOwner, DataExportError, readCiphertextExport, serializeCiphertextExport, type CiphertextDataExport } from '@/lib/data-portability/ciphertextExport';

export default function CiphertextExport() {
  const { user, loading } = useAuth();
  const manager = useSharedConversation();
  const current = useRef(user?.uid); current.current = user?.uid;
  const operation = useRef<AbortController | null>(null);
  const [consent, setConsent] = useState<string | null>(null);
  const [prepared, setPrepared] = useState<CiphertextDataExport | null>(null);
  const [status, setStatus] = useState<{owner: string; kind: 'busy'|'error'|'download'; message: string} | null>(null);
  const activeOwner = () => current.current && auth?.currentUser?.uid === current.current ? current.current : null;
  useEffect(() => { operation.current?.abort(); operation.current = null; setConsent(null); setPrepared(null); setStatus(null);
    return () => { operation.current?.abort(); }; }, [user?.uid]);
  const shown = prepared?.ownerUid === user?.uid ? prepared : null;
  const shownStatus = status?.owner === user?.uid ? status : null;
  const prepare = async () => {
    if (!user || loading || consent !== user.uid || operation.current) return;
    const owner = user.uid, controller = new AbortController(); operation.current = controller;
    setPrepared(null); setStatus({owner,kind:'busy',message:'Reading encrypted local records…'});
    try {
      if (manager.uid !== owner || manager.session?.getSnapshot().pending) throw new Error('session-not-idle');
      const value = await readCiphertextExport(owner,{currentOwner:activeOwner,signal:controller.signal});
      if (!controller.signal.aborted && activeOwner() === owner) { setPrepared(value); setStatus(null); }
    } catch (error) { if (!controller.signal.aborted && activeOwner() === owner) setStatus({owner,kind:'error',message:error instanceof DataExportError ? error.message : 'Export could not be prepared. Wait for the current reply and check browser storage, then retry. No records were changed.'}); }
    finally { if (operation.current === controller) operation.current = null; }
  };
  const download = () => {
    if (!shown || !user || consent !== user.uid) return;
    try {
      assertExportOwner(shown.ownerUid,{currentOwner:activeOwner,signal:new AbortController().signal});
      const url = URL.createObjectURL(new Blob([serializeCiphertextExport(shown)],{type:'application/json'}));
      try {
        const link = document.createElement('a'); link.href = url; link.download = `koi-ciphertext-export-${shown.exportedAt.slice(0,10)}.json`;
        document.body.appendChild(link); try { link.click(); } finally { link.remove(); }
      } finally { window.setTimeout(() => URL.revokeObjectURL(url),1000); }
      setStatus({owner:user.uid,kind:'download',message:'Download requested. Confirm that your browser saved the file. This is not a restorable backup.'});
    } catch { setPrepared(null); setStatus({owner:user.uid,kind:'error',message:'Download could not be started. Check your current account and browser download permissions, then prepare a new export.'}); }
  };
  // Controls stay in this card; the prepared preview is shown below it as a white paper capsule.
  return <><section className="neo-card p-6 mb-6" aria-labelledby="ciphertext-export-title">
    <h2 id="ciphertext-export-title" className="font-bold text-xl">Encrypted data export</h2>
    <p className="my-3">Download a copy of your owner-tagged encrypted messages and available conversation snapshot from this device. This is a data export, not a restorable backup or a readable report.</p>
    <p className="text-sm my-3">Message content stays encrypted. Account and conversation IDs, sender roles and timestamps are readable metadata. Decryption has not been verified. The original encryption key is required to read the content; the file contains no key and cannot recover a lost key. This file cannot be restored through Import.</p>
    <p className="text-sm my-3">Up to 200 records / 2 MiB. This is a point-in-time local storage copy, not cloud data or a guarantee that every in-memory change has been saved.</p>
    <div className="no-print">
    <label className="flex gap-3 my-4"><input type="checkbox" checked={!!user && consent===user.uid} disabled={!user||loading||shownStatus?.kind==='busy'} onChange={e=>{setConsent(e.target.checked?user?.uid??null:null);setPrepared(null);setStatus(null);}} />
      I understand the metadata and key limitations and want to prepare a private data export.</label>
    <button type="button" className="neo-btn-primary w-full" disabled={!user||loading||consent!==user.uid||shownStatus?.kind==='busy'} onClick={()=>void prepare()}>Prepare data export</button>
    {shown && <button type="button" className="neo-btn-secondary w-full mt-3" style={{whiteSpace:'normal'}} onClick={download}>Download ciphertext data JSON</button>}
    </div>
  </section>
    {(shown || shownStatus) && <section className="koi-paper mb-6" data-testid="export-preview-paper" aria-label="Data export preview">
      {shown && <p role="status">Prepared: {shown.counts.messages} encrypted messages and {shown.counts.conversationSnapshots} conversation snapshots. No wellness report was generated.</p>}
      {shownStatus && <p className={shown ? 'mt-3' : ''} role={shownStatus.kind==='error'?'alert':'status'}>{shownStatus.message}</p>}
    </section>}
  </>;
}
