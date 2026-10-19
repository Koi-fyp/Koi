'use client';
import { useEffect, useRef, useState } from 'react';
import NeoButton from '@/components/ui/NeoButton';
import NeoCard from '@/components/ui/NeoCard';
import NeoInput from '@/components/ui/NeoInput';
import { PlatformClientError, type ProfessionalApi } from '@/lib/platform/client';
import type { CapabilitiesDTO } from '@/lib/platform/types';
import type { Connection, Page, PatientAssignment, PatientDetail } from '@/lib/platform/patient-types';
import QuestionnaireRunner from './QuestionnaireRunner';
export default function PatientWorkspace({ api, onDenied }: { api: ProfessionalApi; onDenied: () => void }) {
  const [caps, setCaps] = useState<CapabilitiesDTO | null>(null), [items, setItems] = useState<PatientAssignment[]>([]), [cursor, setCursor] = useState<string | null>(null);
  const [connections, setConnections] = useState<Connection[]>([]), [requestCursor, setRequestCursor] = useState<string | null>(null), [detail, setDetail] = useState<PatientDetail | null>(null);
  const [invite, setInvite] = useState(''), [psychologist, setPsychologist] = useState(''), [consent, setConsent] = useState(false), [busy, setBusy] = useState(false), [error, setError] = useState(''), [message, setMessage] = useState('');
  const alive = useRef(true), working = useRef(false);
  const failure = (e: unknown) => { if (!alive.current) return; if (e instanceof PlatformClientError && [401, 403, 404].includes(e.status)) onDenied(); else setError(e instanceof PlatformClientError && e.status === 409 ? 'This action has changed, expired or was already completed. Refresh before trying again.' : 'The service is unavailable or the request could not be accepted. Retry after checking your details.'); };
  const load = async (next?: string) => {
    const page = await api.request<Page<PatientAssignment>>(`/api/v1/patient/assignments${next ? `?cursor=${encodeURIComponent(next)}` : ''}`);
    if (alive.current) { setItems(old => next ? [...old, ...page.items] : page.items); setCursor(page.next_cursor); }
  };
  const loadRequests = async (next?: string) => {
    const page = await api.request<Page<Connection>>(`/api/v1/connection-requests${next ? `?cursor=${encodeURIComponent(next)}` : ''}`);
    if (alive.current) { setConnections(old => next ? [...old, ...page.items] : page.items); setRequestCursor(page.next_cursor); }
  };
  const refresh = async () => {
    const access = await api.request<CapabilitiesDTO>('/api/v1/me/capabilities'); if (!alive.current) return;
    setCaps(access); if (access.capabilities.expert_directory) await Promise.all([load(), loadRequests()]);
  };
  useEffect(() => {
    alive.current = true;
    const fragment = new URLSearchParams(window.location.hash.slice(1)).get('invite');
    if (fragment) { setInvite(fragment); window.history.replaceState(null, '', window.location.pathname); }
    void refresh().catch(failure);
    return () => { alive.current = false; };
  }, [api]);
  const run = async (action: () => Promise<void>) => { if (working.current) return; working.current = true; setBusy(true); setError(''); try { await action(); } catch (e) { failure(e); } finally { working.current = false; if (alive.current) setBusy(false); } };
  if (!caps) return <div role="status" className="professional-status"><span className="neo-spinner" aria-hidden="true" />Loading your account…{error && <p role="alert">{error}</p>}</div>;
  if (!caps.capabilities.expert_directory) return <NeoCard className="professional-card"><h1>General account registration required</h1><p>Use an existing server-registered General account to accept invitations or apply to a practice. Registration delivery is not available in this slice.</p></NeoCard>;
  if (detail && 'attempt' in detail) return <QuestionnaireRunner key={detail.attempt.id} api={api} initial={detail} onDenied={onDenied} onClose={() => { setDetail(null); void load().catch(failure); }} />;
  if (detail && 'acknowledgement' in detail) return <NeoCard className="professional-card"><h1>Questionnaire submitted</h1><p>Your responses were received on {new Date(detail.acknowledgement.submitted_at).toLocaleString()}.</p><NeoButton onClick={() => setDetail(null)}>Back to assignments</NeoButton></NeoCard>;
  return <><h1>Your care</h1>{error && <p role="alert" className="professional-error">{error}</p>}<p role="status">{busy ? <><span className="neo-spinner" aria-hidden="true" /> Working…</> : message}</p>
    <NeoCard className="professional-card"><h2>Join a practice</h2><p>Your account stays yours. A care relationship gives that practice access to questionnaires you submit to it.</p><label><input type="checkbox" checked={consent} onChange={e => setConsent(e.target.checked)} /> I consent to joining this practice and sharing my assigned questionnaire responses with its psychologist (care-consent-v1).</label>
      <form className="professional-stack" onSubmit={e => { e.preventDefault(); void run(async () => { await api.request(`/api/v1/patient-invitations/${encodeURIComponent(invite)}/redeem`, 'POST', { consent_version: 'care-consent-v1' }); if (alive.current) { setInvite(''); setMessage('Invitation accepted.'); await refresh(); } }); }}><NeoInput label="Invitation code" aria-label="Invitation code" value={invite} autoComplete="off" onChange={e => setInvite(e.target.value.trim())} required /><NeoButton type="submit" disabled={busy || !consent}>Accept invitation</NeoButton></form>
      <form className="professional-stack" onSubmit={e => { e.preventDefault(); void run(async () => { await api.request('/api/v1/connection-requests', 'POST', { psychologist_uid: psychologist, consent_version: 'care-consent-v1' }); if (alive.current) { setMessage('Application requested.'); await loadRequests(); } }); }}><NeoInput label="Psychologist account ID shared by the practice" aria-label="Psychologist account ID" value={psychologist} onChange={e => setPsychologist(e.target.value.trim())} required /><NeoButton type="submit" disabled={busy || !consent}>Apply to practice</NeoButton></form>
    </NeoCard>
    <NeoCard className="professional-card"><h2>Applications</h2>{!connections.length && <p>No applications yet.</p>}{connections.map(c => <div className="professional-question" key={c.id}><p>{c.psychologist_uid} — {c.state.replaceAll('_', ' ')}</p>
      {c.state === 'requested' && <NeoButton disabled={busy} onClick={() => void run(async () => { await api.request(`/api/v1/connection-requests/${c.id}/transition`, 'POST', { expected_revision: c.revision, to_state: 'awaiting_demo_payment' }); await loadRequests(); })}>Continue application</NeoButton>}
      {c.state === 'awaiting_demo_payment' && <><p>Simulated payment only. No money or financial details are collected.</p><NeoButton disabled={busy} onClick={() => void run(async () => { await api.request(`/api/v1/connection-requests/${c.id}/demo-payment`, 'POST', { expected_revision: c.revision }); await loadRequests(); })}>Complete demo step</NeoButton></>}
      {!['accepted', 'rejected', 'withdrawn'].includes(c.state) && <NeoButton variant="ghost" disabled={busy} onClick={() => { if (window.confirm('Withdraw this application?')) void run(async () => { await api.request(`/api/v1/connection-requests/${c.id}/transition`, 'POST', { expected_revision: c.revision, to_state: 'withdrawn' }); await loadRequests(); }); }}>Withdraw application</NeoButton>}
    </div>)}{requestCursor && <NeoButton onClick={() => void run(() => loadRequests(requestCursor))}>More applications</NeoButton>}</NeoCard>
    {!!caps.active_patient_relationships.length && <NeoCard className="professional-card"><h2>Assigned questionnaires</h2>{!items.length && <p>No questionnaires are available yet.</p>}{items.map(item => <div key={item.id} className="professional-row professional-between"><div><strong>{item.title.en ?? item.title.ur ?? item.title['ur-Latn']}</strong><p>{item.state === 'assigned' ? 'Not started' : item.state.replaceAll('_', ' ')}</p></div><NeoButton disabled={busy} onClick={() => void run(async () => { const value = await api.request<PatientDetail>(`/api/v1/patient/assignments/${item.id}`); if (alive.current) setDetail(value); })}>{item.state === 'submitted' ? 'View acknowledgement' : 'Open questionnaire'}</NeoButton></div>)}{cursor && <NeoButton disabled={busy} onClick={() => void run(() => load(cursor))}>More questionnaires</NeoButton>}</NeoCard>}
    <NeoButton variant="ghost" disabled={busy} onClick={() => void run(refresh)}>Refresh your care</NeoButton>
  </>;
}
