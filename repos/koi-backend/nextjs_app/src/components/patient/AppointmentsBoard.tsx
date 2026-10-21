'use client';
import { useEffect, useId, useRef, useState } from 'react';
import NeoButton from '@/components/ui/NeoButton';
import NeoCard from '@/components/ui/NeoCard';
import NeoInput from '@/components/ui/NeoInput';
import { useConfirmedAction, type ConfirmOptions } from '@/components/ui/feedback';
import { useUnreadState } from '@/components/messaging/useUnreadMessages';
import type { ProfessionalApi } from '@/lib/platform/client';
import type { Appointment } from '@/lib/platform/community-types';
import type { Page } from '@/lib/platform/patient-types';
import { appointmentStateLabels, changedByOtherParty, proposalIssues, sortAppointments } from '@/lib/platform/appointments';
import { unreadStore } from '@/lib/platform/messaging/unread-store';

export const appointmentSteps: Record<Appointment['state'], ConfirmOptions & { success: string }> = {
  requested: { title: 'Request an appointment?', description: 'Your psychologist will be notified and can propose a time.', confirmLabel: 'Request appointment', success: 'Appointment requested' },
  proposed: { title: 'Propose this time?', description: 'The patient will be notified and can accept the proposed time.', confirmLabel: 'Propose time', success: 'Time proposed' },
  confirmed: { title: 'Accept the proposed time?', description: 'The appointment is confirmed and your psychologist is notified.', confirmLabel: 'Accept proposed time', success: 'Appointment confirmed' },
  rejected: { title: 'Reject this appointment request?', description: 'The patient is notified. They can submit a new request.', confirmLabel: 'Reject request', tone: 'danger', success: 'Request rejected' },
  completed: { title: 'Mark this appointment completed?', description: 'The appointment is recorded as completed.', confirmLabel: 'Mark completed', success: 'Appointment completed' },
  cancelled: { title: 'Cancel this appointment?', description: 'The other party is notified. To reschedule, request a new appointment after cancellation.', confirmLabel: 'Cancel appointment', cancelLabel: 'Keep appointment', tone: 'danger', success: 'Appointment cancelled' },
};
export interface BoardRelationship { id: string; label: string }
type Row = Appointment & { party: string };
export const MAX_BOARD_RELATIONSHIPS = 25;
const when = (iso: string) => new Date(iso).toLocaleString();

/** All appointments across the given relationships, latest change first. Authority stays with the server. */
export default function AppointmentsBoard({ api, relationships, professional = false, onError, title = 'All appointments' }: { api: ProfessionalApi; relationships: BoardRelationship[]; professional?: boolean; onError: (error: unknown) => void; title?: string }) {
  const [items, setItems] = useState<Row[]>([]), [loaded, setLoaded] = useState(false), [busy, setBusy] = useState(false), [error, setError] = useState('');
  const [drafts, setDrafts] = useState<Record<string, { start: string; end: string }>>({}), [target, setTarget] = useState(relationships[0]?.id ?? '');
  const alive = useRef(true), working = useRef(false), ask = useConfirmedAction(), id = useId();
  const key = relationships.map(r => r.id).join('|');
  const shown = relationships.slice(0, MAX_BOARD_RELATIONSHIPS);
  const load = async () => {
    const pages = await Promise.all(shown.map(r => api.request<Page<Appointment>>(`/api/v1/relationships/${encodeURIComponent(r.id)}/appointments`).then(page => page.items.map(a => ({ ...a, party: r.label })))));
    if (alive.current) { setItems(pages.flat()); setLoaded(true); }
  };
  const run = async (fn: () => Promise<void>) => { if (working.current) return; working.current = true; setBusy(true); setError(''); try { await fn(); } catch (e) { if (alive.current) { setError('Unable to complete this action. Refresh to check access and the latest state.'); onError(e); } } finally { working.current = false; if (alive.current) setBusy(false); } };
  useEffect(() => { alive.current = true; setLoaded(false); if (!relationships.some(r => r.id === target)) setTarget(relationships[0]?.id ?? ''); void run(load); return () => { alive.current = false; }; }, [api, key]);
  // Reuse the single nav poller: a new appointment notice from the other party reloads the list.
  const notices = useUnreadState().notices, fresh = changedByOtherParty(notices), freshKey = [...fresh].sort().join('|');
  useEffect(() => { if (loaded && freshKey) void run(load); }, [freshKey]);
  const settle = (appointmentId: string) => { const ids = notices.filter(n => n.kind === 'appointment_change' && !n.read_at && 'appointment_id' in n.reference && n.reference.appointment_id === appointmentId).map(n => n.id); if (ids.length) void unreadStore.markRead?.(ids); };
  const transition = (a: Row, state: Appointment['state']) => ask(appointmentSteps[state], run, async () => {
    const draft = drafts[a.id];
    const dates = state === 'proposed' && draft ? { starts_at: new Date(draft.start).toISOString(), ends_at: new Date(draft.end).toISOString() } : {};
    await api.request(`/api/v1/appointments/${a.id}/transition`, 'POST', { expected_revision: a.revision, to_state: state, ...dates });
    settle(a.id); await load();
  });
  const request = () => ask(appointmentSteps.requested, run, async () => { await api.request('/api/v1/appointments', 'POST', { relationship_id: target }); await load(); });
  const sorted = sortAppointments(items);
  return <NeoCard className="professional-card" aria-busy={busy}>
    <h3>{title}</h3><p>This human appointment workflow is separate from your KOI companion. It is not an emergency support service.</p>
    {busy && <p role="status"><span className="neo-spinner" aria-hidden="true" />Loading…</p>}{error && <p role="alert">{error}</p>}
    {relationships.length > MAX_BOARD_RELATIONSHIPS && <p className="professional-muted">Showing appointments for the first {MAX_BOARD_RELATIONSHIPS} loaded relationships.</p>}
    {!professional && relationships.length > 0 && <div className="professional-row">
      {relationships.length > 1 && <label className="professional-label">Psychologist for the request<select className="neo-input" value={target} onChange={e => setTarget(e.target.value)}>{relationships.map(r => <option key={r.id} value={r.id}>{r.label}</option>)}</select></label>}
      <NeoButton disabled={busy || !target} onClick={() => void request()}>Request appointment</NeoButton>
    </div>}
    {loaded && !items.length && <p>{professional ? 'No appointment requests yet. Patients request appointments from their care workspace.' : 'No appointments yet. Request one and your psychologist will propose a time.'}</p>}
    <ul className="care-notification-list" aria-label="Appointments, latest change first">{sorted.map((a, index) => {
      const draft = drafts[a.id] ?? { start: '', end: '' }, issues = proposalIssues(draft.start, draft.end), invalid = !!(issues.start || issues.end), started = !!(draft.start || draft.end);
      const setDraft = (patch: Partial<typeof draft>) => setDrafts(old => ({ ...old, [a.id]: { ...draft, ...patch } }));
      return <li key={a.id} className="care-notification" data-unread={fresh.has(a.id) || undefined}>
        {fresh.has(a.id) && <span className="care-new-badge">New</span>}
        <div className="professional-row"><span className={`care-chip care-chip--${a.state}`}>{appointmentStateLabels[a.state]}</span>{index === 0 && <span className="care-chip care-chip--latest">Latest</span>}{relationships.length > 1 && <span style={{ overflowWrap: 'anywhere' }}>{a.party}</span>}</div>
        <p>{a.starts_at && a.ends_at ? <>{when(a.starts_at)} – {when(a.ends_at)}</> : 'No time proposed yet'} · Updated <time dateTime={a.updated_at}>{when(a.updated_at)}</time></p>
        {professional && a.state === 'requested' && <div className="professional-stack">
          <div className="professional-row">
            <NeoInput aria-label="Proposed start time" label="Proposed start (local time)" type="datetime-local" value={draft.start} aria-invalid={started && !!issues.start} aria-describedby={`${id}-${a.id}-start`} onChange={e => setDraft({ start: e.target.value })} />
            <NeoInput aria-label="Proposed end time" label="Proposed end (local time)" type="datetime-local" value={draft.end} aria-invalid={started && !!issues.end} aria-describedby={`${id}-${a.id}-end`} onChange={e => setDraft({ end: e.target.value })} />
          </div>
          {started && <div className="professional-error"><p id={`${id}-${a.id}-start`}>{issues.start}</p><p id={`${id}-${a.id}-end`}>{issues.end}</p></div>}
          <p className="professional-muted">Start must be in the future; the appointment lasts 10 to 240 minutes.</p>
        </div>}
        <div className="professional-row">
          {professional && a.state === 'requested' && <NeoButton disabled={busy || invalid} onClick={() => void transition(a, 'proposed')}>Propose time</NeoButton>}
          {!professional && a.state === 'proposed' && <NeoButton disabled={busy} onClick={() => void transition(a, 'confirmed')}>Accept proposed time</NeoButton>}
          {professional && ['requested', 'proposed'].includes(a.state) && <NeoButton disabled={busy} onClick={() => void transition(a, 'rejected')}>Reject request</NeoButton>}
          {professional && a.state === 'confirmed' && a.ends_at && Date.parse(a.ends_at) <= Date.now() && <NeoButton disabled={busy} onClick={() => void transition(a, 'completed')}>Mark completed</NeoButton>}
          {['requested', 'proposed', 'confirmed'].includes(a.state) && <NeoButton disabled={busy} variant="ghost" onClick={() => void transition(a, 'cancelled')}>Cancel</NeoButton>}
        </div>
      </li>;
    })}</ul>
    <p>To reschedule, cancel the current appointment and submit a new request. Availability conflicts are not checked.</p>
    <NeoButton disabled={busy} variant="ghost" onClick={() => void run(load)}>Refresh appointments</NeoButton>
  </NeoCard>;
}
