'use client';
import { useEffect, useRef, useState } from 'react';
import { EmailAuthProvider, reauthenticateWithCredential, type User } from 'firebase/auth';
import NeoButton from '@/components/ui/NeoButton';
import NeoCard from '@/components/ui/NeoCard';
import NeoInput from '@/components/ui/NeoInput';
import { PlatformClientError } from '@/lib/platform/client';

interface Pending { uid: string; promise: Promise<void>; resolve: () => void; reject: (error: unknown) => void }
/** Client freshness is only a prompt hint. The server still checks auth_time and authority. */
export function useRecentAuthentication(uid: string | null, currentUser: () => User | null) {
  const pending = useRef<Pending | null>(null);
  const [request, setRequest] = useState<Pending | null>(null);
  const finish = (r: Pending, error?: unknown) => {
    if (pending.current !== r) return;
    pending.current = null; setRequest(null); error ? r.reject(error) : r.resolve();
  };
  useEffect(() => {
    if (pending.current && pending.current.uid !== uid) finish(pending.current, new PlatformClientError(401, 'unauthenticated'));
  }, [uid]);
  useEffect(() => () => { pending.current?.reject(new PlatformClientError(401, 'unauthenticated')); pending.current = null; }, []);
  const beforeMutation = async () => {
    const user = currentUser();
    if (!uid || user?.uid !== uid) throw new PlatformClientError(401, 'unauthenticated');
    let authTime: number;
    try { authTime = Number((await user.getIdTokenResult()).claims.auth_time); }
    catch (error: any) { throw new PlatformClientError(error?.code === 'auth/network-request-failed' ? 503 : 401, 'unauthenticated'); }
    if (currentUser()?.uid !== uid) throw new PlatformClientError(401, 'unauthenticated');
    if (Number.isFinite(authTime) && Date.now() / 1000 - authTime < 240 && authTime <= Date.now() / 1000 + 30) return;
    if (pending.current) return pending.current.promise;
    let resolve: () => void, reject: (error: unknown) => void;
    const promise = new Promise<void>((yes, no) => { resolve = yes; reject = no; });
    const r = { uid, promise, resolve: resolve!, reject: reject! };
    pending.current = r; setRequest(r); return promise;
  };
  return { beforeMutation, dialog: request && request.uid === uid ? <ReauthenticationDialog request={request} currentUser={currentUser} finish={finish} /> : null };
}
function ReauthenticationDialog({ request, currentUser, finish }: { request: Pending; currentUser: () => User | null; finish: (r: Pending, error?: unknown) => void }) {
  const dialog = useRef<HTMLDialogElement>(null);
  const [password, setPassword] = useState(''), [busy, setBusy] = useState(false), [error, setError] = useState('');
  useEffect(() => { dialog.current?.showModal(); return () => dialog.current?.close(); }, []);
  const cancel = () => finish(request, new PlatformClientError(0, 'reauth_cancelled'));
  return <dialog ref={dialog} className="professional-auth-dialog" aria-label="Confirm your sign-in" onCancel={event => { event.preventDefault(); if (!busy) cancel(); }}>
    <NeoCard className="professional-card"><h2>Confirm your sign-in</h2><p>Enter your password to continue saving or publishing. Your unsaved edits stay here.</p>
      {error && <p role="alert" className="professional-error">{error}</p>}
      <form className="professional-stack" onSubmit={async event => {
        event.preventDefault(); if (busy) return; setBusy(true); setError('');
        try {
          const user = currentUser();
          if (user?.uid !== request.uid || !user.email) throw new Error('Identity changed');
          await reauthenticateWithCredential(user, EmailAuthProvider.credential(user.email, password));
          if (currentUser()?.uid !== request.uid) throw new Error('Identity changed');
          finish(request);
        } catch { setError('Could not confirm your sign-in. Check your password and connection.'); }
        finally { setPassword(''); setBusy(false); }
      }}><NeoInput label="Confirm password" aria-label="Confirm password" type="password" autoComplete="current-password" value={password} required disabled={busy} onChange={event => setPassword(event.target.value)} />
        <div className="professional-row"><NeoButton type="submit" loading={busy}>Continue</NeoButton><NeoButton type="button" variant="ghost" disabled={busy} onClick={cancel}>Cancel</NeoButton></div>
      </form>
    </NeoCard>
  </dialog>;
}
