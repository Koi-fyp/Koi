'use client';
import { useEffect, useRef, useState } from 'react';
import NeoButton from '@/components/ui/NeoButton';
import NeoCard from '@/components/ui/NeoCard';
import NeoInput from '@/components/ui/NeoInput';
import { useProfessionalAuth } from '@/lib/platform/professional-auth';
import { professionalApi, type ProfessionalApi } from '@/lib/platform/client';
import { useAccessMonitor } from '@/lib/platform/access-monitor';
import { useRecentAuthentication } from '@/components/professional/RecentAuthentication';
import PatientWorkspace from './PatientWorkspace';
function CareContent({ auth, expired, beforeMutation, generation }: { auth: ReturnType<typeof useProfessionalAuth>; expired: () => void; beforeMutation: () => Promise<void>; generation: number }) {
  const current = useRef(auth.currentUser), recent = useRef(beforeMutation);
  current.current = auth.currentUser; recent.current = beforeMutation;
  const [client, setClient] = useState<{ api: ProfessionalApi; generation: number } | null>(null);
  // Rotate/abort requests on an authorization hint, but retain the workspace so
  // it can reconcile relationship access before discarding an authorized draft.
  useEffect(() => { const api = professionalApi(auth.user!.uid, () => current.current(), fetch, () => recent.current()); setClient({ api, generation }); return () => api.dispose(); }, [auth.user!.uid, generation]);
  return client ? <PatientWorkspace api={client.api} accessReady={client.generation === generation} onDenied={expired} /> : <div role="status" className="professional-status"><span className="neo-spinner" aria-hidden="true" />Loading care access…</div>;
}
function Session({ auth, expired, beforeMutation }: { auth: ReturnType<typeof useProfessionalAuth>; expired: () => void; beforeMutation: () => Promise<void> }) {
  const access = useAccessMonitor(auth.user!.uid, auth.currentUser);
  return access.ready ? <CareContent generation={access.generation} auth={auth} expired={expired} beforeMutation={beforeMutation} /> : <NeoCard className="professional-card"><div role="status"><span className="neo-spinner" aria-hidden="true" /> Checking care access…</div><p>Care content stays locked while the access connection is unavailable. An existing registered General account is required.</p><NeoButton onClick={() => window.location.reload()}>Reconnect</NeoButton></NeoCard>;
}
export default function PatientApp() {
  const auth = useProfessionalAuth(), recent = useRecentAuthentication(auth.user?.uid ?? null, auth.currentUser);
  const [expired, setExpired] = useState(false), [email, setEmail] = useState(''), [password, setPassword] = useState(''), [busy, setBusy] = useState(false), [error, setError] = useState('');
  if (auth.loading) return <div role="status" className="professional-status"><span className="neo-spinner" aria-hidden="true" />Checking your session…</div>;
  if (auth.error) return <NeoCard className="professional-card"><h1>Care sign-in unavailable</h1><NeoButton onClick={() => window.location.reload()}>Retry</NeoButton></NeoCard>;
  if (!auth.user || expired) return <NeoCard className="professional-card professional-narrow"><h1>{expired ? 'Care access changed' : 'Care sign-in'}</h1><p>Use your existing registered General account. Your companion session stays separate.</p>{error && <p role="alert">{error}</p>}<form className="professional-stack" onSubmit={async e => { e.preventDefault(); setBusy(true); setError(''); try { await auth.signIn(email, password); setExpired(false); } catch { setError('Sign-in failed. Check your credentials and connection.'); } finally { setPassword(''); setBusy(false); } }}><NeoInput label="Email" aria-label="Email" type="email" autoComplete="username" required value={email} onChange={e => setEmail(e.target.value)} /><NeoInput label="Password" aria-label="Password" type="password" autoComplete="current-password" required value={password} onChange={e => setPassword(e.target.value)} /><NeoButton type="submit" loading={busy}>Sign in</NeoButton></form></NeoCard>;
  return <><div className="professional-row professional-between"><span>Care account</span><NeoButton variant="ghost" onClick={() => { setExpired(true); void auth.signOut(); }}>Sign out</NeoButton></div><Session key={auth.user.uid} auth={auth} expired={() => setExpired(true)} beforeMutation={recent.beforeMutation} />{recent.dialog}</>;
}
