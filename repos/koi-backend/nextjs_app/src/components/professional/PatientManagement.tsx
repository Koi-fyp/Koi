'use client';
import { useEffect, useRef, useState } from 'react';
import NeoButton from '@/components/ui/NeoButton';
import NeoCard from '@/components/ui/NeoCard';
import NeoInput from '@/components/ui/NeoInput';
import { PlatformClientError, type ProfessionalApi } from '@/lib/platform/client';
import type { Connection, Page, Relationship } from '@/lib/platform/patient-types';
import type { Submission } from '@/lib/platform/professional-types';
import CareConversation from '../patient/CareConversation';
import AppointmentsBoard from '../patient/AppointmentsBoard';
import SubmissionNotifications from './SubmissionNotifications';
import PatientHistory from './PatientHistory';
import SubmissionReview from './SubmissionReview';
import PublishedVersionPicker from './PublishedVersionPicker';
import type { VersionDTO } from '@/lib/platform/types';
import { navigateWorkspace } from '@/components/platform/WorkspaceFrame';
import { useConfirm, useConfirmedAction } from '@/components/ui/feedback';
import { revealCareElement, useCareReveal } from '@/components/platform/care-focus';
export default function PatientManagement({ api, organizationId, publishedVersionId, onDenied, onOpenConversation, selectedRelationshipId, selectedSubmissionId, knownVersions, active = true, view = 'patients' }: { knownVersions?: VersionDTO[]; selectedRelationshipId?: string | null; selectedSubmissionId?: string | null; active?: boolean; onOpenConversation?: (patient: Relationship) => void; view?: 'patients' | 'submissions' | 'appointments'; api: ProfessionalApi; organizationId: string; publishedVersionId?: string; onDenied: (error: unknown) => void }) {
  const [history, setHistory] = useState<Relationship | null>(null);
  const [search, setSearch] = useState(''), [stateFilter, setStateFilter] = useState('all');
  const [conversation, setConversation] = useState<string | null>(null);
  const [patients, setPatients] = useState<Relationship[]>([]), [applications, setApplications] = useState<Connection[]>([]), [submissions, setSubmissions] = useState<Submission[]>([]);
  const [cursors, setCursors] = useState<Record<string, string | null>>({}), [selected, setSelected] = useState<string[]>([]), [all, setAll] = useState(false);
  const [version, setVersion] = useState(publishedVersionId ?? ''), [intended, setIntended] = useState(''), [invite, setInvite] = useState<{ invitation_id: string; token: string; expires_at: string } | null>(null);
  const [invitationExpiry] = useState(() => new Date(Date.now() + 6 * 86400000).toISOString());
  const [submission, setSubmission] = useState<string | null>(null), [busy, setBusy] = useState(false), [message, setMessage] = useState(''), [error, setError] = useState('');
  const alive = useRef(true), running = useRef(false), confirm = useConfirm(), ask = useConfirmedAction();
  const failure = (e: unknown) => {
    if (!alive.current) return;
    if (e instanceof PlatformClientError && [401, 403].includes(e.status)) { onDenied(e); return; }
    setError(e instanceof PlatformClientError && e.status === 409 ? 'This record changed or the request conflicts. Refresh before trying again; unsaved review text is kept.' : 'Could not complete this action. Verify practice, patient, version and service availability.');
  };
  const load = async (kind: 'patients' | 'applications' | 'submissions', next?: string) => {
    const path = kind === 'applications' ? '/api/v1/connection-requests' : `/api/v1/professional/${kind === 'patients' ? 'patient-relationships' : 'submissions'}`;
    const page = await api.request<Page<any>>(`${path}?${kind === 'applications' ? '' : `organization_id=${encodeURIComponent(organizationId)}&`}${next ? `cursor=${encodeURIComponent(next)}` : ''}`);
    if (!alive.current) return;
    if (kind === 'patients') setPatients(old => next ? [...old, ...page.items] : page.items);
    if (kind === 'applications') setApplications(old => next ? [...old, ...page.items] : page.items);
    if (kind === 'submissions') setSubmissions(old => next ? [...old, ...page.items] : page.items);
    setCursors(old => ({ ...old, [kind]: page.next_cursor }));
  };
  const refresh = async () => { await Promise.all([load('patients'), load('applications'), load('submissions')]); };
  useEffect(() => { alive.current = true; void refresh().catch(failure); return () => { alive.current = false; }; }, [api, organizationId]);
  useEffect(() => { if (publishedVersionId) setVersion(publishedVersionId); }, [publishedVersionId]);
  const run = async (fn: () => Promise<void>) => { if (running.current) return; running.current = true; setBusy(true); setError(''); setMessage(''); try { await fn(); } catch (e) { failure(e); } finally { running.current = false; if (alive.current) setBusy(false); } };
  const historyOpener = useRef<HTMLElement | null>(null), appointmentOpener = useRef<HTMLElement | null>(null), reviewOpener = useRef<HTMLElement | null>(null);
  const [reviewReveal, setReviewReveal] = useState(0), [appointmentReveal, setAppointmentReveal] = useState(0);
  useEffect(() => {
    if (view !== 'appointments' || !active || selectedRelationshipId === undefined) return;
    const match = patients.find(patient => patient.id === selectedRelationshipId && patient.state === 'active');
    setConversation(match?.id ?? null);
  }, [selectedRelationshipId, patients, view, active]);
  useCareReveal('selected-patient', history, active && view === 'patients');
  useCareReveal('patient-appointments', conversation ? `${conversation}:${appointmentReveal}` : null, active && view === 'appointments' && !!conversation);
  useCareReveal('selected-submission', reviewReveal, active && !!submission && view !== 'appointments');
  useCareReveal('created-invitation', invite, active && view === 'patients');
  const returnTo = (target: HTMLElement | null) => requestAnimationFrame(() => revealCareElement(target));
  const reviewCanClose = async () => {
    const fields = document.querySelectorAll<HTMLTextAreaElement>('#selected-submission textarea[aria-label="Psychologist conclusion"], #selected-submission textarea[aria-label="Review feedback"]');
    return !Array.from(fields).some(field => field.value.trim()) || await confirm({ title: 'Discard your unsaved review text?', description: 'Your conclusion and feedback for the open submission have not been saved.', confirmLabel: 'Discard review text', cancelLabel: 'Keep editing', tone: 'danger' });
  };
  const inspect = async (id: string) => {
    if (id !== submission && !(await reviewCanClose())) return;
    reviewOpener.current = document.activeElement as HTMLElement;
    setSubmission(id); setReviewReveal(n => n + 1);
  };
  // "View submission" links from the dashboard open the review directly.
  useEffect(() => { if (active && view === 'submissions' && selectedSubmissionId && selectedSubmissionId !== submission) void inspect(selectedSubmissionId); }, [active, view, selectedSubmissionId]);
  const roster = patients.filter(p => p.patient_uid.toLocaleLowerCase().includes(search.toLocaleLowerCase()) && (stateFilter === 'all' || p.state === stateFilter));
  return <section className="professional-stack" aria-label="Practice patients and submissions">
    {error && <p role="alert" className="professional-error">{error}</p>}
    <p role="status">{busy ? <><span className="neo-spinner" aria-hidden="true" /> Working...</> : message}</p>
    {submission && <section id="selected-submission" tabIndex={-1} aria-label="Selected submission" className="professional-stack care-result-panel" hidden={view === 'appointments'}>
      <div className="professional-row professional-between"><h2>Selected submission</h2><NeoButton variant="ghost" onClick={async () => { if (await reviewCanClose()) { setSubmission(null); returnTo(reviewOpener.current); } }}>Back to submission list</NeoButton></div>
      <SubmissionReview key={submission} id={submission} api={api} onError={failure} />
    </section>}
    {view === 'submissions' && <><SubmissionNotifications api={api} organizationId={organizationId} onInspect={inspect} onError={failure} />
      <NeoCard className="professional-card"><h2 id="submissions">Submitted questionnaires</h2>
        {!submissions.length && <p>No submissions yet. Assigned questionnaires appear here after a patient submits their answers.</p>}
        {submissions.map(s => <div key={s.id} className="professional-row professional-between"><span>{s.patient_uid} · {new Date(s.submitted_at).toLocaleString()}</span><NeoButton disabled={busy} onClick={() => inspect(s.id)}>Inspect submission</NeoButton></div>)}
        {cursors.submissions && <NeoButton onClick={() => void run(() => load('submissions', cursors.submissions!))}>More submissions</NeoButton>}
      </NeoCard></>}
    {view === 'appointments' && selectedRelationshipId && !conversation && patients.length > 0 && <p role="status">This patient is not available for appointments in the loaded active roster.</p>}
    {view === 'appointments' && conversation && <section id="patient-appointments" tabIndex={-1} aria-labelledby="patient-appointments-heading" className="professional-stack care-result-panel">
      <div className="professional-row professional-between"><h2 id="patient-appointments-heading">Appointments: {patients.find(p => p.id === conversation)?.patient_uid ?? conversation}</h2><NeoButton variant="ghost" onClick={() => { setConversation(null); navigateWorkspace('/professional?view=appointments'); returnTo(appointmentOpener.current); }}>Back to patient selection</NeoButton></div>
      <CareConversation key={conversation} mode="appointments" relationshipId={conversation} label={patients.find(p => p.id === conversation)?.patient_uid} professional api={api} onError={failure} />
    </section>}
    {view === 'appointments' && active && !conversation && <AppointmentsBoard api={api} professional relationships={patients.filter(p => p.state === 'active').map(p => ({ id: p.id, label: p.patient_uid }))} onError={failure} />}
    <div hidden={view === 'submissions'} className={history && view === 'patients' ? 'care-patient-layout' : 'professional-stack'}>
      <NeoCard className="professional-card"><h2 id="patients">{view === 'appointments' ? 'Select a patient for appointments' : 'Patients and assignments'}</h2>
        <p>{patients.filter(p => p.state === 'active').length} active in loaded roster / {patients.filter(p => p.state === 'closed').length} closed</p>
        <div className="professional-grid"><NeoInput aria-label="Search loaded patient accounts" label="Search loaded patient accounts" value={search} onChange={e => setSearch(e.target.value)} />
          <label>Relationship status<select className="neo-input" value={stateFilter} onChange={e => setStateFilter(e.target.value)}><option value="all">All</option><option value="active">Active</option><option value="closed">Closed / historical</option></select></label></div>
        {!patients.length && <p>No patients yet. Invite a General account or accept an application below.</p>}
        {!!patients.length && !roster.length && <p>No patients match these filters. Change the search or relationship status.</p>}
        {roster.map(p => <article key={p.id} className="professional-question care-patient-row" data-selected={history?.id === p.id || conversation === p.id ? 'true' : undefined}>
          <label className="professional-row"><input type="checkbox" aria-label={`Select ${p.patient_uid} for assignment`} hidden={view === 'appointments'} disabled={p.state !== 'active' || busy || all} checked={selected.includes(p.id)} onChange={e => setSelected(old => e.target.checked ? [...old, p.id] : old.filter(id => id !== p.id))} /><strong>{p.patient_uid}</strong><span className="professional-badge">{p.state}</span></label>
          <div className="professional-row">
            {view === 'patients' && <NeoButton aria-expanded={history?.id === p.id} aria-controls="selected-patient" onClick={event => { historyOpener.current = event.currentTarget; setHistory({ ...p }); }}>Patient details</NeoButton>}
            {p.state === 'active' && (view === 'appointments'
              ? <NeoButton aria-controls="patient-appointments" aria-expanded={conversation === p.id} onClick={event => { appointmentOpener.current = event.currentTarget; setConversation(p.id); setAppointmentReveal(n => n + 1); navigateWorkspace(`/professional?view=appointments&relationship=${encodeURIComponent(p.id)}`); }}>Manage appointments</NeoButton>
              : <><a className="neo-btn-secondary" onClick={() => onOpenConversation?.(p)} href={`/professional?view=messages&relationship=${encodeURIComponent(p.id)}#messages`}>Open conversation</a><a className="professional-link" href={`/professional?view=appointments&relationship=${encodeURIComponent(p.id)}`}>Appointments</a></>)}
            {view === 'patients' && p.state === 'active' && <NeoButton variant="ghost" disabled={busy} onClick={() => void ask({ title: 'Close this patient relationship?', description: 'Care access ends immediately; professional history is retained.', confirmLabel: 'Close relationship', tone: 'danger', success: 'Relationship closed' }, run, async () => { await api.request(`/api/v1/professional/patient-relationships/${p.id}/close`, 'POST', { expected_revision: p.revision }); setSelected(old => old.filter(id => id !== p.id)); setConversation(null); setHistory(null); await refresh(); })}>Close relationship</NeoButton>}
          </div>
        </article>)}
        {cursors.patients && <NeoButton onClick={() => void run(() => load('patients', cursors.patients!))}>More patients</NeoButton>}
      </NeoCard>
      {history && view === 'patients' && <aside id="selected-patient" tabIndex={-1} aria-labelledby="selected-patient-heading" className="professional-stack care-result-panel">
        <div className="professional-row professional-between"><h2 id="selected-patient-heading">Patient details: {history.patient_uid}</h2><NeoButton variant="ghost" onClick={() => { setHistory(null); returnTo(historyOpener.current); }}>Close patient details</NeoButton></div>
        <PatientHistory key={history.id + history.revision} api={api} patient={history} onInspect={inspect} onError={failure} />
      </aside>}
    </div>
    <div hidden={view !== 'patients'} className="professional-stack">
      <NeoCard className="professional-card"><h2>Assign a published questionnaire</h2><p>Select active patients in the roster, then choose a saved published version. Drafts cannot be assigned.</p>
        <p role="status">{all ? 'All active patients will receive an assignment.' : `${selected.length} patient${selected.length === 1 ? '' : 's'} selected for assignment.`}</p>
        <label><input type="checkbox" checked={all} onChange={e => setAll(e.target.checked)} /> Assign to all active patients (snapshot at assignment time)</label>
        <PublishedVersionPicker api={api} organizationId={organizationId} knownVersions={knownVersions} value={version} onChange={setVersion} onError={failure} disabled={busy} active={active && view === 'patients'} />
        <NeoButton disabled={busy || !version || (!all && !selected.length)} onClick={() => void ask({ title: 'Assign this published questionnaire?', description: `${all ? 'Every active patient' : `${selected.length} selected patient${selected.length === 1 ? '' : 's'}`} will receive a new independent assignment. Repeat assignments start a new attempt.`, confirmLabel: 'Assign questionnaire', success: 'Assignments created' }, run, async () => { const result = await api.request<{ assignment_ids: string[] }>('/api/v1/professional/assignments', 'POST', { organization_id: organizationId, questionnaire_version_id: version, target: all ? { kind: 'all_active' } : { kind: 'selected', relationship_ids: selected } }); if (alive.current) setMessage(`${result.assignment_ids.length} independent assignments created.`); })}>Assign published questionnaire</NeoButton>
      </NeoCard>
      <div className="professional-grid">
        <details className="care-disclosure"><summary>Invitations</summary><NeoCard className="professional-card"><h3>Invite a registered General account</h3><p>Invitations expire within seven days and can be used once. Share the link securely with the intended person.</p>
          <NeoInput label="Intended account UID (optional)" aria-label="Intended account UID (optional)" value={intended} onChange={e => setIntended(e.target.value.trim())} />
          <NeoButton disabled={busy} onClick={() => void run(async () => { const result = await api.request<any>('/api/v1/professional/patient-invitations', 'POST', { organization_id: organizationId, ...(intended ? { intended_uid: intended } : {}), expires_at: invitationExpiry }); if (alive.current) setInvite(result); })}>Create secure invitation</NeoButton>
          {invite && <div id="created-invitation" tabIndex={-1} className="professional-question"><h3>Invitation ready to share</h3><label className="professional-label">Single-use invitation link<input className="neo-input" aria-label="Single-use invitation link" readOnly value={`${window.location.origin}/patient#invite=${invite.token}`} onFocus={e => e.target.select()} /></label><p>Expires {new Date(invite.expires_at).toLocaleString()}</p><NeoButton variant="ghost" disabled={busy} onClick={() => void ask({ title: 'Revoke this invitation?', description: 'The invitation link stops working immediately.', confirmLabel: 'Revoke invitation', tone: 'danger', success: 'Invitation link revoked' }, run, async () => { await api.request(`/api/v1/professional/patient-invitations/${invite.invitation_id}/revoke`, 'POST', { expected_revision: 1 }); if (alive.current) { setInvite(null); setMessage('Invitation revoked.'); } })}>Revoke invitation</NeoButton></div>}
        </NeoCard></details>
        <details className="care-disclosure"><summary>Applications ({applications.length} loaded)</summary><NeoCard className="professional-card"><h3>Applications</h3>{!applications.length && <p>No applications yet.</p>}
          {applications.map(a => <div key={a.id} className="professional-question"><p>{a.applicant_uid} · {a.state.replaceAll('_', ' ')}</p>{a.state === 'pending_psychologist_review' && <div className="professional-row">{(['accepted', 'rejected'] as const).map(state => <NeoButton key={state} disabled={busy} onClick={() => void ask(state === 'accepted' ? { title: 'Accept this application?', description: 'The applicant becomes an active patient of your practice and gains access to care tools.', confirmLabel: 'Accept application', success: 'Application accepted' } : { title: 'Reject this application?', description: 'The applicant is notified that the practice declined.', confirmLabel: 'Reject application', tone: 'danger', success: 'Application rejected' }, run, async () => { await api.request(`/api/v1/connection-requests/${a.id}/transition`, 'POST', { expected_revision: a.revision, to_state: state }); await refresh(); })}>{state === 'accepted' ? 'Accept application' : 'Reject application'}</NeoButton>)}</div>}</div>)}
          {cursors.applications && <NeoButton onClick={() => void run(() => load('applications', cursors.applications!))}>More applications</NeoButton>}
        </NeoCard></details>
      </div>
    </div>
    <NeoButton variant="ghost" disabled={busy} onClick={() => void run(refresh)}>Refresh current records</NeoButton>
  </section>;
}
