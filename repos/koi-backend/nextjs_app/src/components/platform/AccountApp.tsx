'use client';
import { useEffect, useState } from 'react';
import NeoButton from '@/components/ui/NeoButton';
import NeoCard from '@/components/ui/NeoCard';
import NeoInput from '@/components/ui/NeoInput';
import { useProfessionalAuth } from '@/lib/platform/professional-auth';
import PlatformNavigation from './PlatformNavigation';
import CareLink from './CareLink';
import CareEntryAccess from './CareEntryAccess';
import { careEntryCopy, careEntryIntent, type CareEntryIntent } from '@/lib/platform/care-entry';
export default function AccountApp() {
  const auth = useProfessionalAuth();
  const [intent, setIntent] = useState<CareEntryIntent | null | undefined>(undefined);
  useEffect(() => {
    const sync = () => setIntent(careEntryIntent(new URLSearchParams(window.location.search).get('entry')));
    sync(); window.addEventListener('popstate', sync);
    return () => window.removeEventListener('popstate', sync);
  }, []);
  const [email, setEmail] = useState(''), [password, setPassword] = useState(''), [busy, setBusy] = useState(false), [error, setError] = useState('');
  if (auth.loading || intent === undefined) return <p role="status"><span className="neo-spinner" aria-hidden="true" />Restoring your account…</p>;
  return <NeoCard className={`professional-card ${auth.user ? 'care-account-page' : 'professional-narrow'}`}><h1>{intent ? careEntryCopy[intent].heading : 'KOI Care account'}</h1>{intent && <p>{careEntryCopy[intent].description}</p>}<p>Sign in to find a professional or open your care workspace. Companion history stays in its existing session; signing in here does not import or share it.</p><details className="care-disclosure"><summary>How KOI identities and access work</summary><dl className="care-account-states care-profile-editor"><div><dt>Anonymous companion</dt><dd>Your separate companion identity and history.</dd></div><div><dt>Registered care account</dt><dd>Find experts, apply to practices and receive invitations.</dd></div><div><dt>Active patient access</dt><dd>An active care relationship adds questionnaires, human messaging and appointment requests to your account.</dd></div><div><dt>Verified psychologist access</dt><dd>Practice tools require server verification and active practice membership.</dd></div></dl></details>{(error || auth.error) && <p role="alert">{error || 'Account sign-in is unavailable. Check the local platform setup.'}</p>}
    {auth.user ? <><p>Signed in as {auth.user.email ?? 'your account'}</p><>{intent ? <CareEntryAccess intent={intent} auth={auth} /> : <PlatformNavigation overview />}</><NeoButton variant="ghost" disabled={busy} onClick={async () => { setBusy(true); try { await auth.signOut(); } catch { setError('Sign-out failed. Retry.'); } finally { setBusy(false); } }}>Sign out of account</NeoButton></> : <form className="professional-stack" onSubmit={async e => { e.preventDefault(); if (busy) return; setBusy(true); setError(''); try { await auth.signIn(email, password); } catch { setError('Sign-in failed. Check your email, password and connection.'); } finally { setPassword(''); setBusy(false); } }}>
      <NeoInput aria-label="Email" label="Email" type="email" autoComplete="username" required value={email} onChange={e => setEmail(e.target.value)} /><NeoInput aria-label="Password" label="Password" type="password" autoComplete="current-password" required value={password} onChange={e => setPassword(e.target.value)} /><NeoButton loading={busy} type="submit" disabled={auth.error}>Sign in</NeoButton><p>Use an existing registered account. Public registration is not available yet.</p>
    </form>}<CareLink href="/?home=1" variant="secondary">Back to KOI home</CareLink>
  </NeoCard>;
}
