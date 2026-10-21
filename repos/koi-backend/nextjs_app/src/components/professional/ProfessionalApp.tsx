'use client';
import { useEffect, useRef, useState } from 'react';
import NeoButton from '@/components/ui/NeoButton';
import NeoCard from '@/components/ui/NeoCard';
import NeoInput from '@/components/ui/NeoInput';
import { professionalApi, type ProfessionalApi } from '@/lib/platform/client';
import { useProfessionalAuth } from '@/lib/platform/professional-auth';
import ProfessionalWorkspace, { WorkspaceLoading } from './ProfessionalWorkspace';
import { useRecentAuthentication } from './RecentAuthentication';
import { FeedbackProviders } from '@/components/ui/feedback';

function Session({ uid, currentUser, expired, beforeMutation }: { uid: string; currentUser: ReturnType<typeof useProfessionalAuth>['currentUser']; expired: () => void; beforeMutation: () => Promise<void> }) {
  const current = useRef(currentUser); current.current = currentUser;
  const recent = useRef(beforeMutation); recent.current = beforeMutation;
  const [api, setApi] = useState<ProfessionalApi | null>(null);
  useEffect(() => { const client = professionalApi(uid, () => current.current(), fetch, () => recent.current()); setApi(client); return () => client.dispose(); }, [uid]);
  return api ? <ProfessionalWorkspace api={api} onSessionExpired={expired} /> : <WorkspaceLoading />;
}
export default function ProfessionalApp() {
  const auth = useProfessionalAuth();
  const recent = useRecentAuthentication(auth.user?.uid ?? null, auth.currentUser);
  const [email, setEmail] = useState(''), [password, setPassword] = useState('');
  const [expired, setExpired] = useState(false), [busy, setBusy] = useState(false), [error, setError] = useState('');
  if (auth.loading) return <WorkspaceLoading text="Checking your professional session…" />;
  if (auth.error) return <NeoCard className="professional-card"><h1>Professional sign-in unavailable</h1><p>The professional account service is not configured or could not restore your session.</p><NeoButton onClick={() => window.location.reload()}>Retry sign-in</NeoButton></NeoCard>;
  if (!auth.user || expired) return <NeoCard className="professional-card professional-narrow"><h1>{expired ? 'Sign in again' : 'Professional sign-in'}</h1><p>{expired ? 'Your session needs fresh authentication. Unsaved edits have been cleared; saved drafts remain available.' : 'Use your existing approved psychologist account. Professional sign-in is separate from your companion session.'}</p>
    {error && <p role="alert" className="professional-error">{error}</p>}
    <form className="professional-stack" onSubmit={async event => {
      event.preventDefault(); if (busy) return; setBusy(true); setError('');
      try { await auth.signIn(email, password); setExpired(false); setEmail(''); }
      catch { setError('Sign-in failed. Check your credentials and connection, then try again.'); }
      finally { setPassword(''); setBusy(false); }
    }}>
      <NeoInput label="Email" aria-label="Email" type="email" autoComplete="username" value={email} required disabled={busy} onChange={event => setEmail(event.target.value)} />
      <NeoInput label="Password" aria-label="Password" type="password" autoComplete="current-password" value={password} required disabled={busy} onChange={event => setPassword(event.target.value)} />
      <NeoButton type="submit" loading={busy}>Sign in</NeoButton>
    </form><p className="professional-muted">An account alone does not grant practice access. Verification is handled by the authorized administrator.</p>
  </NeoCard>;
  return <FeedbackProviders><div className="professional-row professional-between"><span className="professional-muted">Professional session</span><NeoButton variant="ghost" onClick={() => { void auth.signOut().catch(() => setError('Sign-out failed. Try again.')); }}>Sign out of workspace</NeoButton></div>{error && <p role="alert">{error}</p>}
    <Session key={auth.user.uid} uid={auth.user.uid} currentUser={auth.currentUser} expired={() => setExpired(true)} beforeMutation={recent.beforeMutation} />{recent.dialog}
  </FeedbackProviders>;
}
