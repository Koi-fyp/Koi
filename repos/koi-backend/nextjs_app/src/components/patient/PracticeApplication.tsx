'use client';
import { useEffect, useRef, useState } from 'react';
import NeoCard from '@/components/ui/NeoCard';
import NeoButton from '@/components/ui/NeoButton';
import CareLink from '@/components/platform/CareLink';
import { useCareReveal } from '@/components/platform/care-focus';
import { PlatformClientError, type ProfessionalApi } from '@/lib/platform/client';
import type { CapabilitiesDTO } from '@/lib/platform/types';
import { CARE_CONSENT_VERSION, type Connection } from '@/lib/platform/patient-types';
import { applicationLabel } from '@/lib/platform/care-state';
import type { Expert } from './ExpertDirectory';

export default function PracticeApplication({ api, selectedId, initialProfile, caps, connections, active, onProfile, onSubmitted, onUnauthorized }: {
  api: ProfessionalApi; selectedId: string | null; initialProfile: Expert | null; caps: CapabilitiesDTO; connections: Connection[]; active: boolean;
  onProfile: (profile: Expert) => void; onSubmitted: (connection: Connection) => void; onUnauthorized: (error: unknown) => void;
}) {
  const [verified, setVerified] = useState<{ api: ProfessionalApi; profile: Expert } | null>(null);
  const [consent, setConsent] = useState(false), [busy, setBusy] = useState(false), [error, setError] = useState('');
  const [result, setResult] = useState<Connection | null>(null);
  const alive = useRef(true), currentApi = useRef(api), currentId = useRef(selectedId), callbacks = useRef({ onProfile, onSubmitted, onUnauthorized }), working = useRef(false);
  currentApi.current = api; currentId.current = selectedId; callbacks.current = { onProfile, onSubmitted, onUnauthorized };
  useEffect(() => { alive.current = true; return () => { alive.current = false; }; }, []);
  useEffect(() => { setConsent(false); setResult(null); setError(''); }, [selectedId]);
  useEffect(() => {
    if (!selectedId || !active) return;
    let live = true;
    setVerified(null); setError('');
    void api.request<Expert>(`/api/v1/experts/${encodeURIComponent(selectedId)}`).then(profile => {
      if (!live || currentApi.current !== api || currentId.current !== selectedId) return;
      if (profile.id !== selectedId || typeof profile.display_name !== 'string' || typeof profile.bio !== 'string' || typeof profile.accepting_new_patients !== 'boolean') throw new Error('Invalid profile');
      setVerified({ api, profile }); callbacks.current.onProfile(profile);
    }).catch(failure => {
      if (!live || currentApi.current !== api) return;
      setError('This psychologist profile could not be confirmed. Choose another psychologist or retry when connected.');
      if (failure instanceof PlatformClientError && failure.status === 401) callbacks.current.onUnauthorized(failure);
    });
    return () => { live = false; };
  }, [api, selectedId, active]);
  useCareReveal('practice-application', selectedId, active);
  useCareReveal('application-result', result?.id, active);
  const ready = active && verified?.api === api && verified.profile.id === selectedId;
  const profile = ready ? verified.profile : initialProfile?.id === selectedId ? initialProfile : null;
  const existing = connections.find(connection => connection.psychologist_uid === selectedId);
  const record = result?.psychologist_uid === selectedId && (!existing || result.revision > existing.revision) ? result : existing;
  const alreadyActive = caps.active_patient_relationships.some(r => r.psychologist_uid === selectedId);
  return <NeoCard id="practice-application" tabIndex={-1} className="professional-card">
    <h2>Apply to a psychologist</h2>
    {!selectedId ? <><p>Choose an available psychologist to start your application. Their name and practice profile will appear here.</p><CareLink variant="primary" href="/patient?view=experts#experts">Find a Psychologist</CareLink></> : <>
      {profile && <div className="professional-question"><h3 dir="auto">{profile.display_name}</h3><p className="professional-label">Practice profile</p><p dir="auto" style={{ whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>{profile.bio}</p><p>{profile.accepting_new_patients ? 'Accepting new patients' : 'Not currently accepting new patients'}</p></div>}
      {!ready && !error && <p role="status">Confirming the selected psychologist...</p>}
      <CareLink href="/patient?view=experts#experts">Choose a different psychologist</CareLink>
      {alreadyActive && <p>You already have active care with this psychologist. Open My Psychologist to manage your care.</p>}
      {record && <div id="application-result" tabIndex={-1} className="professional-question" role="status"><h3>{result?.id === record.id ? 'Application recorded' : 'Application on record'}</h3><p>{applicationLabel(record, caps)}</p><p>Use the application status and available next steps below. Sending an application does not activate patient access.</p>{record.state === 'accepted' && !alreadyActive && <p>No active care relationship is currently available for this practice. Rejoining a previous practice is not supported by this workflow. You can choose another psychologist.</p>}</div>}
      {error && <div role="alert" className="professional-error"><p>{error}</p>{!ready && <CareLink variant="secondary" href="/patient?view=experts#experts">Return to the directory</CareLink>}</div>}
      <form className="professional-stack" aria-label="Practice application" onSubmit={event => {
        event.preventDefault();
        if (!ready || !profile?.accepting_new_patients || !consent || alreadyActive || record || working.current) return;
        working.current = true; setBusy(true); setError('');
        void api.request<Connection>('/api/v1/connection-requests', 'POST', { psychologist_uid: selectedId, consent_version: CARE_CONSENT_VERSION }).then(connection => {
          if (!alive.current || currentApi.current !== api || currentId.current !== selectedId) return;
          if (connection.applicant_uid !== caps.uid || connection.psychologist_uid !== selectedId) throw new Error('Invalid application response');
          setResult(connection); callbacks.current.onSubmitted(connection);
        }).catch(failure => {
          if (!alive.current || currentApi.current !== api || currentId.current !== selectedId) return;
          if (failure instanceof PlatformClientError && failure.status === 409) setError('This practice cannot accept a new application for this account right now. An existing or previous care relationship, or another application conflict, may prevent reapplying. No new application was confirmed. Check your application history or choose another psychologist. Rejoining a previous practice is not supported by the current workflow.');
          else if (failure instanceof PlatformClientError && [403, 404].includes(failure.status)) { setVerified(null); setError('This psychologist is no longer available for applications. Choose another psychologist from the directory.'); }
          else if (failure instanceof PlatformClientError && failure.status === 401) callbacks.current.onUnauthorized(failure);
          else setError('Your application was not confirmed. Check your connection and retry.');
        }).finally(() => { working.current = false; if (alive.current) setBusy(false); });
      }}>
        <p>By applying, you agree to join this practice if accepted and share the questionnaires assigned by this psychologist with them. Your anonymous KOI Companion history remains separate.</p>
        <label><input type="checkbox" required checked={consent} disabled={busy || !!record || alreadyActive} onChange={event => setConsent(event.target.checked)} /> I consent to joining this practice and sharing my assigned questionnaire responses.</label>
        <NeoButton type="submit" loading={busy} disabled={!ready || !profile?.accepting_new_patients || !consent || !!record || alreadyActive}>Send Application</NeoButton>
        {!consent && !record && <p>Select the consent checkbox to enable Send Application once the profile is confirmed.</p>}
      </form>
    </>}
  </NeoCard>;
}
