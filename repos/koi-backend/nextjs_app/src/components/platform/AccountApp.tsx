'use client';
import { useState } from 'react';
import NeoButton from '@/components/ui/NeoButton';
import NeoCard from '@/components/ui/NeoCard';
import NeoInput from '@/components/ui/NeoInput';
import { useProfessionalAuth } from '@/lib/platform/professional-auth';
import PlatformNavigation from './PlatformNavigation';
export default function AccountApp() {
  const auth = useProfessionalAuth();
  const [email, setEmail] = useState(''), [password, setPassword] = useState(''), [busy, setBusy] = useState(false), [error, setError] = useState('');
  if (auth.loading) return <p role="status"><span className="neo-spinner" aria-hidden="true" />Restoring your account…</p>;
  return <NeoCard className="professional-card professional-narrow"><h1>KOI account</h1><p>Sign in to find a professional or open your care workspace. Companion history stays in its existing session; signing in here does not import or share it.</p>{(error || auth.error) && <p role="alert">{error || 'Account sign-in is unavailable. Check the local platform setup.'}</p>}
    {auth.user ? <><p>Signed in as {auth.user.email ?? 'your account'}</p><PlatformNavigation expanded /><NeoButton variant="ghost" disabled={busy} onClick={async () => { setBusy(true); try { await auth.signOut(); } catch { setError('Sign-out failed. Retry.'); } finally { setBusy(false); } }}>Sign out of account</NeoButton></> : <form className="professional-stack" onSubmit={async e => { e.preventDefault(); if (busy) return; setBusy(true); setError(''); try { await auth.signIn(email, password); } catch { setError('Sign-in failed. Check your email, password and connection.'); } finally { setPassword(''); setBusy(false); } }}>
      <NeoInput aria-label="Email" label="Email" type="email" autoComplete="username" required value={email} onChange={e => setEmail(e.target.value)} /><NeoInput aria-label="Password" label="Password" type="password" autoComplete="current-password" required value={password} onChange={e => setPassword(e.target.value)} /><NeoButton loading={busy} type="submit" disabled={auth.error}>Sign in</NeoButton><p>Use an existing registered account. Public registration is not available yet.</p>
    </form>}<a href="/?home=1" className="professional-link">Back to KOI home</a>
  </NeoCard>;
}
