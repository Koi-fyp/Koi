'use client';
import { useEffect, useRef, useState } from 'react';
import NeoButton from '@/components/ui/NeoButton';
import NeoCard from '@/components/ui/NeoCard';
import type { ProfessionalApi } from '@/lib/platform/client';
import type { Page } from '@/lib/platform/patient-types';
import type { HumanMessage } from '@/lib/platform/community-types';
import AppointmentsBoard from './AppointmentsBoard';

export default function CareConversation({ api, relationshipId, professional = false, onError, mode = 'all', label }: { mode?: 'all' | 'appointments'; api: ProfessionalApi; relationshipId: string; professional?: boolean; onError: (error: unknown) => void; label?: string }) {
  const [messages, setMessages] = useState<HumanMessage[]>([]), [cursor, setCursor] = useState<string | null>(null), [body, setBody] = useState('');
  const [busy, setBusy] = useState(false), [loaded, setLoaded] = useState(false), [error, setError] = useState('');
  const alive = useRef(true), working = useRef(false);
  const load = async (next?: string) => {
    const page = await api.request<Page<HumanMessage>>(`/api/v1/relationships/${encodeURIComponent(relationshipId)}/messages${next ? `?cursor=${encodeURIComponent(next)}` : ''}`);
    if (!alive.current) return;
    setMessages(old => next ? [...old, ...page.items] : page.items); setCursor(page.next_cursor); setLoaded(true);
  };
  const run = async (fn: () => Promise<void>) => { if (working.current) return; working.current = true; setBusy(true); setError(''); try { await fn(); } catch (e) { if (alive.current) { setError('Unable to complete this action. Refresh to check access and the latest state.'); onError(e); } } finally { working.current = false; if (alive.current) setBusy(false); } };
  useEffect(() => { alive.current = true; if (mode === 'all') void run(() => load()); return () => { alive.current = false; }; }, [api, relationshipId, mode]);
  const board = <AppointmentsBoard api={api} professional={professional} title="Appointments" relationships={[{ id: relationshipId, label: label ?? relationshipId }]} onError={onError} />;
  if (mode === 'appointments') return board;
  return <div className="professional-stack"><NeoCard className="professional-card"><h3>Messages</h3><p>This human conversation is separate from your KOI companion. It is not an emergency support service.</p>
    {busy && <p role="status"><span className="neo-spinner" aria-hidden="true" />Loading…</p>}{error && <p role="alert">{error}</p>}
    {loaded && !messages.length && <p>No messages yet.</p>}
    {[...messages].sort((a, b) => a.created_at.localeCompare(b.created_at)).map(m => <div className="professional-question" key={m.id}><p>{m.sender_uid} · <time dateTime={m.created_at}>{new Date(m.created_at).toLocaleString()}</time></p><p style={{ whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>{m.body}</p></div>)}
    {cursor && <NeoButton disabled={busy} onClick={() => void run(() => load(cursor))}>More messages</NeoButton>}
    <form onSubmit={e => { e.preventDefault(); void run(async () => { await api.request('/api/v1/messages', 'POST', { relationship_id: relationshipId, body }); if (alive.current) setBody(''); await load(); }); }} className="professional-stack"><label>Message<textarea className="neo-input" value={body} maxLength={4000} required onChange={e => setBody(e.target.value)} /></label><NeoButton type="submit" disabled={busy || !body.trim()}>Send message</NeoButton></form>
  </NeoCard>{board}</div>;
}
