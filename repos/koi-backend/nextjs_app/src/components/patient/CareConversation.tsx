'use client';
import { useEffect, useRef, useState } from 'react';
import NeoButton from '@/components/ui/NeoButton';
import NeoCard from '@/components/ui/NeoCard';
import NeoInput from '@/components/ui/NeoInput';
import type { ProfessionalApi } from '@/lib/platform/client';
import type { Page } from '@/lib/platform/patient-types';
import type { Appointment, HumanMessage } from '@/lib/platform/community-types';

export default function CareConversation({ api, relationshipId, professional = false, onError, mode = 'all' }: { mode?: 'all' | 'appointments'; api: ProfessionalApi; relationshipId: string; professional?: boolean; onError: (error: unknown) => void }) {
  const [messages, setMessages] = useState<HumanMessage[]>([]), [appointments, setAppointments] = useState<Appointment[]>([]);
  const [cursors, setCursors] = useState<Record<string, string | null>>({}), [body, setBody] = useState(''), [start, setStart] = useState(''), [end, setEnd] = useState('');
  const [busy, setBusy] = useState(false), [loaded, setLoaded] = useState(false), [error, setError] = useState('');
  const alive = useRef(true), working = useRef(false);
  const load = async (kind: 'messages' | 'appointments', cursor?: string) => {
    const page = await api.request<Page<any>>(`/api/v1/relationships/${encodeURIComponent(relationshipId)}/${kind}${cursor ? `?cursor=${encodeURIComponent(cursor)}` : ''}`);
    if (!alive.current) return;
    if (kind === 'messages') setMessages(old => cursor ? [...old, ...page.items] : page.items);
    else setAppointments(old => cursor ? [...old, ...page.items] : page.items);
    setCursors(old => ({ ...old, [kind]: page.next_cursor }));
  };
  const run = async (fn: () => Promise<void>) => { if (working.current) return; working.current = true; setBusy(true); setError(''); try { await fn(); } catch (e) { if (alive.current) { setError('Unable to complete this action. Refresh to check access and the latest state.'); onError(e); } } finally { working.current = false; if (alive.current) setBusy(false); } };
  const refresh = async () => { await Promise.all([load('messages'), load('appointments')]); if (alive.current) setLoaded(true); };
  useEffect(() => { alive.current = true; void run(refresh); return () => { alive.current = false; }; }, [api, relationshipId]);
  const transition = (a: Appointment, state: Appointment['state']) => run(async () => {
    const dates = state === 'proposed' ? { starts_at: new Date(start).toISOString(), ends_at: new Date(end).toISOString() } : {};
    await api.request(`/api/v1/appointments/${a.id}/transition`, 'POST', { expected_revision: a.revision, to_state: state, ...dates }); await load('appointments');
  });
  return <NeoCard className="professional-card"><h3>{mode === 'appointments' ? 'Appointments' : 'Messages and appointments'}</h3><p>This human conversation is separate from your KOI companion. It is not an emergency support service.</p>
    {busy && <p role="status"><span className="neo-spinner" aria-hidden="true" />Loading…</p>}{error && <p role="alert">{error}</p>}
    <div hidden={mode === 'appointments'} className="professional-stack">{loaded && !messages.length && <p>No messages yet.</p>}
    {[...messages].sort((a, b) => a.created_at.localeCompare(b.created_at)).map(m => <div className="professional-question" key={m.id}><p>{m.sender_uid} · <time dateTime={m.created_at}>{new Date(m.created_at).toLocaleString()}</time></p><p style={{ whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>{m.body}</p></div>)}
    {cursors.messages && <NeoButton disabled={busy} onClick={() => void run(() => load('messages', cursors.messages!))}>More messages</NeoButton>}
    <form onSubmit={e => { e.preventDefault(); void run(async () => { await api.request('/api/v1/messages', 'POST', { relationship_id: relationshipId, body }); if (alive.current) setBody(''); await load('messages'); }); }} className="professional-stack"><label>Message<textarea className="neo-input" value={body} maxLength={4000} required onChange={e => setBody(e.target.value)} /></label><NeoButton type="submit" disabled={busy || !body.trim()}>Send message</NeoButton></form>
    </div><h4>Appointments</h4>{loaded && !appointments.length && <p>No appointments yet.</p>}
    {!professional && <NeoButton disabled={busy} onClick={() => void run(async () => { await api.request('/api/v1/appointments', 'POST', { relationship_id: relationshipId }); await load('appointments'); })}>Request appointment</NeoButton>}
    {professional && <div className="professional-row"><NeoInput aria-label="Proposed start time" label="Proposed start (local time)" type="datetime-local" value={start} onChange={e => setStart(e.target.value)} /><NeoInput aria-label="Proposed end time" label="Proposed end (local time)" type="datetime-local" value={end} onChange={e => setEnd(e.target.value)} /></div>}
    {appointments.map(a => <div className="professional-question" key={a.id}><p>{a.state}{a.starts_at && ` · ${new Date(a.starts_at).toLocaleString()} – ${new Date(a.ends_at!).toLocaleString()}`}</p><div className="professional-row">
      {professional && a.state === 'requested' && <NeoButton disabled={busy || !start || !end} onClick={() => void transition(a, 'proposed')}>Propose time</NeoButton>}
      {!professional && a.state === 'proposed' && <NeoButton disabled={busy} onClick={() => void transition(a, 'confirmed')}>Accept proposed time</NeoButton>}
      {professional && ['requested', 'proposed'].includes(a.state) && <NeoButton disabled={busy} onClick={() => void transition(a, 'rejected')}>Reject request</NeoButton>}
      {professional && a.state === 'confirmed' && a.ends_at && Date.parse(a.ends_at) <= Date.now() && <NeoButton disabled={busy} onClick={() => void transition(a, 'completed')}>Mark completed</NeoButton>}
      {['requested', 'proposed', 'confirmed'].includes(a.state) && <NeoButton disabled={busy} variant="ghost" onClick={() => { if (window.confirm('Cancel this appointment? To reschedule, request a new appointment after cancellation.')) void transition(a, 'cancelled'); }}>Cancel</NeoButton>}
    </div></div>)}{cursors.appointments && <NeoButton disabled={busy} onClick={() => void run(() => load('appointments', cursors.appointments!))}>More appointments</NeoButton>}
    <p>To reschedule, cancel the current appointment and submit a new request. Availability conflicts are not checked.</p><NeoButton disabled={busy} variant="ghost" onClick={() => void run(refresh)}>Refresh conversation</NeoButton>
  </NeoCard>;
}
