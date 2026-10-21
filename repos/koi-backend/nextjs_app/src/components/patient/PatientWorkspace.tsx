'use client';
import { useEffect, useRef, useState } from 'react';
import NeoButton from '@/components/ui/NeoButton';
import NeoCard from '@/components/ui/NeoCard';
import NeoInput from '@/components/ui/NeoInput';
import { PlatformClientError, type ProfessionalApi } from '@/lib/platform/client';
import type { CapabilitiesDTO } from '@/lib/platform/types';
import type { Connection, Page, PatientAssignment, PatientDetail } from '@/lib/platform/patient-types';
import ExpertDirectory, { type Expert } from './ExpertDirectory';
import PracticeApplication from './PracticeApplication';
import ProfessionalEntry from './ProfessionalEntry';
import AppointmentsBoard from './AppointmentsBoard';
import CareNotifications from './CareNotifications';
import QuestionnaireRunner from './QuestionnaireRunner';
import MessagesScreen from '@/components/messaging/MessagesScreen';
import CareLink from '@/components/platform/CareLink';
import { useConfirmedAction } from '@/components/ui/feedback';
import { hasPatientAccess, applicationLabel } from '@/lib/platform/care-state';
import { revealCareElement } from '@/components/platform/care-focus';
import WorkspaceFrame, { generalViews, patientViews, useWorkspaceView, useWorkspaceSearchParam, navigateWorkspace } from '@/components/platform/WorkspaceFrame';
export default function PatientWorkspace({ api, onDenied, accessReady = true }: { api: ProfessionalApi; onDenied: () => void; accessReady?: boolean }) {
  const view = useWorkspaceView(patientViews, 'home');
  const selectedId = useWorkspaceSearchParam('psychologist');
  const [selectedExpert, setSelectedExpert] = useState<Expert | null>(null);
  const [visitedExperts, setVisitedExperts] = useState(false);
  useEffect(() => { if (view === 'experts') setVisitedExperts(true); }, [view]);
  const [caps, setCaps] = useState<CapabilitiesDTO | null>(null), [items, setItems] = useState<PatientAssignment[]>([]), [cursor, setCursor] = useState<string | null>(null);
  const [assignmentsLoaded, setAssignmentsLoaded] = useState(false);
  const [connections, setConnections] = useState<Connection[]>([]), [requestCursor, setRequestCursor] = useState<string | null>(null), [detail, setDetail] = useState<PatientDetail | null>(null);
  const [invite, setInvite] = useState(''), [consent, setConsent] = useState(false), [busy, setBusy] = useState(false), [error, setError] = useState(''), [message, setMessage] = useState('');
  const alive = useRef(true), working = useRef(false), currentApi = useRef(api), epoch = useRef(0), previousAccess = useRef<CapabilitiesDTO | null>(null);
  currentApi.current = api;
  const ask = useConfirmedAction();
  const [verifiedApi, setVerifiedApi] = useState<ProfessionalApi | null>(null), [verifying, setVerifying] = useState(true), [ended, setEnded] = useState(false), [required, setRequired] = useState(false);
  const confirmed = accessReady && verifiedApi === api && !verifying;
  const current = (client: ProfessionalApi, revision: number) => alive.current && currentApi.current === client && epoch.current === revision;
  const replaceHome = () => {
    const url = new URL(window.location.href); url.searchParams.set('view', 'home'); url.hash = '';
    window.history.replaceState(null, '', url); window.dispatchEvent(new PopStateEvent('popstate'));
  };
  const accessFailure = (e: unknown) => {
    if (!alive.current || currentApi.current !== api) return;
    if (e instanceof PlatformClientError && [401, 403, 404].includes(e.status)) onDenied();
    else setError('Care access could not be confirmed. Retry Refresh your care when connected.');
  };
  const failure = (e: unknown) => { if (!alive.current || currentApi.current !== api) return; if (e instanceof PlatformClientError && e.status === 401) onDenied(); else if (e instanceof PlatformClientError && [403, 404].includes(e.status)) { setDetail(null); void refresh().catch(accessFailure); } else setError(e instanceof PlatformClientError && e.status === 409 ? 'This action has changed, expired or was already completed. Refresh before trying again.' : 'The service is unavailable or the request could not be accepted. Retry after checking your details.'); };
  const load = async (next?: string) => {
    const revision = epoch.current;
    const page = await api.request<Page<PatientAssignment>>(`/api/v1/patient/assignments${next ? `?cursor=${encodeURIComponent(next)}` : ''}`);
    if (current(api, revision)) { const ids = new Set(previousAccess.current?.active_patient_relationships.map(r => r.relationship_id)); const allowed = page.items.filter(item => ids.has(item.relationship_id)); setItems(old => next ? [...old, ...allowed] : allowed); setCursor(page.next_cursor); setAssignmentsLoaded(true); }
  };
  const loadRequests = async (next?: string) => {
    const revision = epoch.current;
    const page = await api.request<Page<Connection>>(`/api/v1/connection-requests${next ? `?cursor=${encodeURIComponent(next)}` : ''}`);
    if (current(api, revision)) { const own = page.items.filter(item => item.applicant_uid === previousAccess.current?.uid); setConnections(old => next ? [...old, ...own] : own); setRequestCursor(page.next_cursor); }
  };
  const refresh = async () => {
    if (!alive.current || currentApi.current !== api) return;
    const revision = ++epoch.current;
    setVerifying(true); setError(''); setAssignmentsLoaded(false);
    const access = await api.request<CapabilitiesDTO>('/api/v1/me/capabilities');
    if (!current(api, revision)) return;
    const before = previousAccess.current;
    const patient = hasPatientAccess(access);
    const ids = new Set(access.active_patient_relationships.map(r => r.relationship_id));
    setDetail(old => old && patient && ids.has(old.assignment.relationship_id) ? old : null);
    setItems(old => patient ? old.filter(item => ids.has(item.relationship_id)) : []);
    if (!patient) setCursor(null);
    if (before && hasPatientAccess(before) && !patient) { setEnded(true); replaceHome(); }
    if (patient) {
      setEnded(false); setRequired(false);
      if (before && !hasPatientAccess(before) && ['home', 'applications'].includes(new URLSearchParams(window.location.search).get('view') ?? 'home')) replaceHome();
    }
    previousAccess.current = access;
    setCaps(access); setVerifiedApi(api); setVerifying(false);
    if (access.account_state === 'registered' && access.capabilities.expert_directory) {
      await Promise.all([patient ? load() : Promise.resolve(), loadRequests()]);
    }
  };
  useEffect(() => {
    alive.current = true;
    const fragment = new URLSearchParams(window.location.hash.slice(1)).get('invite');
    if (fragment) { setInvite(fragment); window.history.replaceState(null, '', window.location.pathname); window.dispatchEvent(new PopStateEvent('popstate')); }
    if (accessReady) void refresh().catch(accessFailure);
    return () => { alive.current = false; epoch.current++; };
  }, [api, accessReady]);
  const run = async (action: () => Promise<void>) => { if (working.current || !confirmed) return; working.current = true; setBusy(true); setError(''); try { await action(); } catch (e) { failure(e); } finally { working.current = false; if (alive.current) setBusy(false); } };
  const patient = !!caps && hasPatientAccess(caps);
  const previousMode = useRef<boolean | null>(null);
  const protectedView = ['care', 'questionnaires', 'messages', 'appointments'].includes(view);
  useEffect(() => {
    if (!confirmed) return;
    if (previousMode.current !== null && previousMode.current !== patient && view === 'home') requestAnimationFrame(() => revealCareElement(document.getElementById('workspace-heading')));
    previousMode.current = patient;
  }, [confirmed, patient, view]);
  useEffect(() => {
    if (confirmed && !patient && protectedView) { setRequired(true); replaceHome(); }
  }, [confirmed, patient, protectedView, view]);
  if (!caps) return <div role="status" className="professional-status"><span className="neo-spinner" aria-hidden="true" />Loading your account...{error && <p role="alert">{error}</p>}<NeoButton variant="ghost" onClick={() => void refresh().catch(accessFailure)}>Retry care access</NeoButton></div>;
  if (confirmed && (caps.account_state !== 'registered' || !caps.capabilities.expert_directory)) return <NeoCard className="professional-card"><h1>General account registration required</h1><p>Use an existing server-registered General account to accept invitations or apply to a practice. Public self-registration is not available. Sign in with an existing registered KOI Care account.</p></NeoCard>;
  const views = confirmed ? patient ? patientViews.filter(v => !['experts', 'applications', 'become-psychologist'].includes(v.id)) : generalViews : [];
  const secondaryViews = confirmed && patient ? generalViews.filter(v => ['experts', 'applications', 'become-psychologist'].includes(v.id)) : [];
  return <WorkspaceFrame contextParams={selectedId ? { psychologist: selectedId } : {}} base="/patient" views={views} secondaryViews={secondaryViews} view={view} workspaceLabel={confirmed ? patient ? 'Patient Dashboard' : 'General User Dashboard' : 'Checking care access'}>
    {!confirmed && <p role="status">Confirming your care permissions... {error}</p>}
    {confirmed && ended && <p role="status" className="professional-question">Your previous care relationship has ended. You can continue using KOI Care to find a psychologist.</p>}
    {confirmed && required && !patient && <p role="status">Active care relationship required. Find a psychologist or accept a practice invitation to access patient tools.</p>}
    {detail && <div hidden={view !== 'questionnaires' || !confirmed} className="professional-stack">
      {'attempt' in detail ? <QuestionnaireRunner key={detail.attempt.id} api={api} initial={detail} paused={!confirmed} onDenied={() => { setDetail(null); void refresh().catch(accessFailure); }} onClose={() => { setDetail(null); void load().catch(failure); }} /> : <NeoCard className="professional-card"><h2>Questionnaire submitted</h2><p>Your responses were received on {new Date(detail.acknowledgement.submitted_at).toLocaleString()}.</p><NeoButton onClick={() => setDetail(null)}>Back to assignments</NeoButton></NeoCard>}
    </div>}
    {confirmed && view === 'home' && (patient ? <div className="professional-grid">
      <NeoCard className="professional-card"><h2>Your care is active</h2>{caps.active_patient_relationships.map(r => <div className="professional-question" key={r.relationship_id}><p><strong>Connected psychologist</strong></p><p>Psychologist account: {r.psychologist_uid}</p></div>)}<div className="care-account-actions"><CareLink variant="primary" href="/patient?view=care#care">My Psychologist</CareLink><CareLink variant="secondary" href="/patient?view=messages#messages">Open care messages</CareLink></div></NeoCard>
      <NeoCard className="professional-card"><h2>Your questionnaires</h2><p>{assignmentsLoaded ? <>{items.filter(item => item.state !== 'submitted').length} awaiting completion in loaded assignments.</> : 'Loading your assignments...'}</p>{items.slice(0, 3).map(item => <p key={item.id}>{item.title.en ?? item.title.ur ?? item.title['ur-Latn']}</p>)}{assignmentsLoaded && !items.length && <p>Your psychologist will assign questionnaires here when ready.</p>}<CareLink variant="primary" href="/patient?view=questionnaires#questionnaires">Open assigned questionnaires</CareLink></NeoCard>
      <NeoCard className="professional-card"><h2>Appointments & updates</h2><p>Manage appointment requests and check care notifications. Requests are confirmed only through the existing appointment workflow.</p><div className="care-account-actions"><CareLink variant="secondary" href="/patient?view=appointments">Manage appointments</CareLink><CareLink variant="secondary" href="/patient?view=notifications#notifications">Check notifications</CareLink></div></NeoCard>
    </div> : <div className="professional-grid"><NeoCard className="professional-card"><h2>Start your care journey</h2><p>Find a psychologist or accept a practice invitation. Your registered account stays the same when care access becomes active.</p><CareLink variant="primary" href="/patient?view=experts#experts">Find a Psychologist</CareLink></NeoCard><NeoCard className="professional-card"><h2>Practice applications</h2><p>Track applications and complete the demo step when requested. Patient tools become available only after the server confirms an active care relationship.</p><div className="care-account-actions"><CareLink variant="secondary" href="/patient?view=applications#applications">My Applications</CareLink><CareLink href="/patient?view=notifications#notifications">Check notifications</CareLink></div></NeoCard></div>)}
    {(view === 'experts' || visitedExperts) && <section id="experts" hidden={!confirmed || view !== 'experts'}><ExpertDirectory active={confirmed && view === 'experts'} api={api} onChoose={expert => {
      setSelectedExpert(expert);
      navigateWorkspace(`/patient?view=applications&psychologist=${encodeURIComponent(expert.id)}#practice-application`);
    }} onError={failure} /></section>}
    {confirmed && view === 'become-psychologist' && <ProfessionalEntry />}
    {confirmed && view === 'notifications' && <section id="notifications"><CareNotifications api={api} onError={failure} /></section>}
    {patient && <section id="messages" hidden={!confirmed || view !== 'messages'}><fieldset disabled={!confirmed || view !== 'messages'} style={{ border: 0, padding: 0, minWidth: 0 }}><MessagesScreen active={confirmed && view === 'messages'} api={api} role="patient" patientRelationships={caps.active_patient_relationships} onError={failure} /></fieldset></section>}
    {confirmed && patient && view === 'care' && <section id="care" className="professional-grid">{caps.active_patient_relationships.map(r => <NeoCard key={r.relationship_id} className="professional-card"><h2>Active care relationship</h2><p>Psychologist account: {r.psychologist_uid}</p><p>Your registered account now has access to this practice's care workflows.</p><a className="professional-link" href="/patient?view=messages#messages">Message your care team</a><a className="professional-link" href="/patient?view=appointments#care">Manage appointments</a></NeoCard>)}</section>}
    {confirmed && patient && view === 'appointments' && <section id="care" className="professional-stack"><AppointmentsBoard api={api} relationships={caps.active_patient_relationships.map(r => ({ id: r.relationship_id, label: `Psychologist ${r.psychologist_uid}` }))} onError={failure} /></section>}
    {error && <p role="alert" className="professional-error">{error}</p>}{(busy || message) && <p role="status">{busy ? <><span className="neo-spinner" aria-hidden="true" /> Working...</> : message}</p>}
    <div hidden={!confirmed || !['home', 'experts', 'applications'].includes(view) || (patient && view === 'home')} className="professional-grid">
    <div className="professional-stack">
      <div hidden={view !== 'applications'}><PracticeApplication api={api} selectedId={selectedId} initialProfile={selectedExpert} caps={caps} connections={connections} active={confirmed && view === 'applications'} onProfile={setSelectedExpert} onUnauthorized={failure} onSubmitted={connection => {
        setConnections(old => [connection, ...old.filter(item => item.id !== connection.id)]);
        void refresh().catch(accessFailure);
      }} /></div>
      <details className="care-disclosure"><summary>Have an invitation code?</summary><div className="care-profile-editor">
        <h2>Join a practice by invitation</h2><p>Accept only an invitation from a practice you intend to join. You agree to share questionnaires assigned by its psychologist; your companion history stays separate.</p>
        <label><input type="checkbox" checked={consent} onChange={e => setConsent(e.target.checked)} /> I consent to joining the inviting practice and sharing my assigned questionnaire responses (care-consent-v1).</label>
        <form className="professional-stack" onSubmit={e => { e.preventDefault(); if (!consent || !invite) return; void run(async () => { await api.request(`/api/v1/patient-invitations/${encodeURIComponent(invite)}/redeem`, 'POST', { consent_version: 'care-consent-v1' }); if (alive.current && currentApi.current === api) { setInvite(''); setMessage('Invitation accepted.'); await refresh(); } }); }}><h3>Accept an invitation</h3><NeoInput label="Invitation code" aria-label="Invitation code" value={invite} autoComplete="off" onChange={e => setInvite(e.target.value.trim())} required /><NeoButton type="submit" disabled={busy || !consent || !invite}>Accept invitation</NeoButton></form>
      </div></details>
    </div>
    <NeoCard className="professional-card"><h2 id="applications">Applications</h2>{!connections.length && <p>No applications yet. Choose an expert and apply, or use a practice invitation.</p>}{connections.map(c => <div className="professional-question" key={c.id}><p>{selectedExpert?.id === c.psychologist_uid ? selectedExpert.display_name : c.psychologist_uid} — <span className="professional-badge">{applicationLabel(c, caps)}</span></p>
      {c.state === 'pending_psychologist_review' && <p>Your demo step is complete. The practice will accept or decline your application. Check notifications for updates.</p>}
      {c.state === 'accepted' && !caps.active_patient_relationships.some(r => r.organization_id === c.organization_id && r.psychologist_uid === c.psychologist_uid) && <p>This application was accepted previously. No active care relationship is currently available for this practice. Application history does not grant patient access.</p>}
      {c.state === 'requested' && <NeoButton disabled={busy} onClick={() => void run(async () => { await api.request(`/api/v1/connection-requests/${c.id}/transition`, 'POST', { expected_revision: c.revision, to_state: 'awaiting_demo_payment' }); await loadRequests(); })}>Continue application</NeoButton>}
      {c.state === 'awaiting_demo_payment' && <><p>Simulated payment only. No money or financial details are collected.</p><NeoButton disabled={busy} onClick={() => void ask({ title: 'Complete the demo payment step?', description: 'This is a simulated step. No money or financial details are collected. The practice then reviews your application.', confirmLabel: 'Complete demo step', success: 'Demo step completed' }, run, async () => { await api.request(`/api/v1/connection-requests/${c.id}/demo-payment`, 'POST', { expected_revision: c.revision }); await loadRequests(); })}>Complete demo step</NeoButton></>}
      {!['accepted', 'rejected', 'withdrawn'].includes(c.state) && <NeoButton variant="ghost" disabled={busy} onClick={() => void ask({ title: 'Withdraw this application?', description: 'The practice will no longer review it. You can apply again later if the practice accepts new patients.', confirmLabel: 'Withdraw application', tone: 'danger', success: 'Application withdrawn' }, run, async () => { await api.request(`/api/v1/connection-requests/${c.id}/transition`, 'POST', { expected_revision: c.revision, to_state: 'withdrawn' }); await loadRequests(); })}>Withdraw application</NeoButton>}
    </div>)}{requestCursor && <NeoButton onClick={() => void run(() => loadRequests(requestCursor))}>More applications</NeoButton>}</NeoCard>
    </div>{confirmed && patient && view === 'questionnaires' && !detail && <NeoCard className="professional-card"><h2 id="questionnaires">Assigned questionnaires</h2>{!assignmentsLoaded && <p role="status">Loading assigned questionnaires...</p>}{assignmentsLoaded && !items.length && <p>No questionnaires have been assigned yet. Your psychologist will assign a form when it is ready.</p>}{items.map(item => <div key={item.id} className="professional-row professional-between"><div><strong>{item.title.en ?? item.title.ur ?? item.title['ur-Latn']}</strong><p>{item.state === 'assigned' ? 'Not started' : item.state.replaceAll('_', ' ')}</p></div><NeoButton disabled={busy} onClick={() => void run(async () => { const revision = epoch.current; const value = await api.request<PatientDetail>(`/api/v1/patient/assignments/${item.id}`); if (current(api, revision)) setDetail(value); })}>{item.state === 'submitted' ? 'View acknowledgement' : item.state === 'assigned' ? 'Start questionnaire' : 'Resume questionnaire'}</NeoButton></div>)}{cursor && <NeoButton disabled={busy} onClick={() => void run(() => load(cursor))}>More questionnaires</NeoButton>}</NeoCard>}
    <NeoButton variant="ghost" disabled={busy} onClick={() => { if (!busy) { setBusy(true); void refresh().catch(accessFailure).finally(() => { if (alive.current) setBusy(false); }); } }}>Refresh your care</NeoButton>
  </WorkspaceFrame>;
}
