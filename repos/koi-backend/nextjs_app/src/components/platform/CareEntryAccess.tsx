'use client';
import { useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { professionalApi } from '@/lib/platform/client';
import { careEntryDestination, type CareEntryIntent } from '@/lib/platform/care-entry';
import type { CapabilitiesDTO } from '@/lib/platform/types';
import type { useProfessionalAuth } from '@/lib/platform/professional-auth';
import NeoButton from '@/components/ui/NeoButton';
import CareLink from './CareLink';

export default function CareEntryAccess({ intent, auth }: { intent: CareEntryIntent; auth: ReturnType<typeof useProfessionalAuth> }) {
  const router = useRouter(), current = useRef(auth.currentUser); current.current = auth.currentUser;
  const uid = auth.user?.uid;
  const [attempt, setAttempt] = useState(0);
  const [result, setResult] = useState<{ uid: string; intent: CareEntryIntent; caps?: CapabilitiesDTO; error?: boolean } | null>(null);
  useEffect(() => {
    setResult(null);
    if (!uid) return;
    let alive = true;
    const api = professionalApi(uid, () => current.current());
    void api.request<CapabilitiesDTO>('/api/v1/me/capabilities').then(caps => {
      if (!alive || current.current()?.uid !== uid) return;
      if (caps.uid !== uid) { setResult({ uid, intent, error: true }); return; }
      const destination = careEntryDestination(intent, caps);
      setResult({ uid, intent, caps });
      if (destination) router.replace(destination);
    }).catch(() => { if (alive && current.current()?.uid === uid) setResult({ uid, intent, error: true }); });
    return () => { alive = false; api.dispose(); };
  }, [uid, intent, attempt, router]);
  if (!result || result.uid !== uid || result.intent !== intent) return <p role="status">Checking your care access...</p>;
  if (result.error) return <div role="alert"><p>Your care access could not be verified. No workspace has been opened. Retry or sign out and sign in again.</p><NeoButton variant="ghost" onClick={() => setAttempt(value => value + 1)}>Retry access check</NeoButton></div>;
  const caps = result.caps!;
  if (careEntryDestination(intent, caps)) return <p role="status">Opening your workspace...</p>;
  return <section aria-label="Care access information" className="professional-question">
    {caps.account_state !== 'registered' ? <p>This account does not currently have registered care access. An existing authorized care account is required.</p> : intent === 'patient' ? <><h2>Patient access requires an active care relationship</h2><p>You can find a psychologist and apply to a practice using General User access. Patient tools become available when your care relationship is active.</p></> : intent === 'psychologist' ? <><h2>Verified psychologist access required</h2><p>This account does not have verified professional workspace access. Practice access requires server verification and active practice membership.</p></> : <><h2>General User access is unavailable</h2><p>This account is not authorized to explore the expert directory.</p></>}
    <div className="care-account-actions">{caps.account_state === 'registered' && caps.capabilities.expert_directory && <CareLink variant="primary" href="/account?entry=general">Continue as General User</CareLink>}<CareLink variant="secondary" href="/account">Back to account overview</CareLink></div>
  </section>;
}
