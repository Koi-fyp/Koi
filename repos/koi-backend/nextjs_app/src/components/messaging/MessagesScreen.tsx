'use client';
import { useCallback, useEffect, useRef, useState } from 'react';
import NeoButton from '@/components/ui/NeoButton';
import type { ProfessionalApi } from '@/lib/platform/client';
import type { HumanMessage } from '@/lib/platform/community-types';
import type { Page, Relationship } from '@/lib/platform/patient-types';
import { desktopPermission, disableDesktop, enableDesktop, desktopEnabled } from '@/lib/platform/messaging/desktop';
import { MAX_CONVERSATIONS, badgeText, dayLabel, mergeMessages, noticeMessageId, preview, shortId, timeLabel, unreadForThread, unreadMessageNotices } from '@/lib/platform/messaging/model';
import { messagePollMs } from '@/lib/platform/messaging/poll-config';
import { createPoller } from '@/lib/platform/messaging/poller';
import { loadThread } from '@/lib/platform/messaging/thread';
import { unreadStore } from '@/lib/platform/messaging/unread-store';
import ChatPane, { type Conversation } from './ChatPane';
import { useUnreadState } from './useUnreadMessages';

interface Thread { messages: HumanMessage[]; capped: boolean; loaded: boolean; error?: string }
export interface PatientConversationSource { relationship_id: string; psychologist_uid: string }
const status = (e: unknown) => (e as { status?: number } | null)?.status;
const stops = (e: unknown) => [401, 403, 404].includes(status(e) ?? 0);

function DesktopToggle() {
  const [, tick] = useState(0), permission = desktopPermission(), on = desktopEnabled();
  if (permission === 'unsupported') return null;
  if (permission === 'denied') return <p className="professional-muted" style={{ fontSize: '.75rem' }}>Desktop notifications are blocked in your browser settings.</p>;
  return on
    ? <NeoButton variant="ghost" onClick={() => { disableDesktop(); tick(n => n + 1); }}>Turn off desktop notifications</NeoButton>
    : <NeoButton variant="ghost" onClick={() => { void enableDesktop().then(() => tick(n => n + 1)); }}>Enable desktop notifications</NeoButton>;
}

/** Messages for one signed-in person: patients pass their active relationships, professionals pass the practice id. */
export default function MessagesScreen({ api, role, patientRelationships, organizationId, onError }: {
  api: ProfessionalApi; role: 'patient' | 'professional'; patientRelationships?: PatientConversationSource[]; organizationId?: string | null; onError: (error: unknown) => void;
}) {
  const [roster, setRoster] = useState<Conversation[] | null>(null), [rosterError, setRosterError] = useState(false), [more, setMore] = useState(false);
  const [threads, setThreads] = useState<Record<string, Thread>>({}), [openId, setOpenId] = useState<string | null>(null);
  const alive = useRef(true), threadsRef = useRef(threads), requested = useRef(new Set<string>()), attempted = useRef(new Set<string>());
  threadsRef.current = threads;
  const unread = useUnreadState();
  const onErrorRef = useRef(onError); onErrorRef.current = onError;
  // Access lost (401/403/404): drop every loaded message before telling the workspace.
  const fail = useCallback((e: unknown) => { if (!alive.current) return; setThreads({}); setRoster([]); onErrorRef.current(e); }, []);

  useEffect(() => { alive.current = true; return () => { alive.current = false; }; }, []);
  // Conversation roster: patients know it from capabilities, professionals read their practice roster.
  useEffect(() => {
    if (role === 'patient') {
      const list = (patientRelationships ?? []).slice(0, MAX_CONVERSATIONS), many = (patientRelationships ?? []).length > 1;
      setMore((patientRelationships ?? []).length > MAX_CONVERSATIONS);
      setRoster(list.map(r => ({ id: r.relationship_id, title: many ? `Your psychologist · ${shortId(r.psychologist_uid)}` : 'Your psychologist', counterpart: r.psychologist_uid })));
      return;
    }
    if (!organizationId) { setRoster([]); return; }
    let live = true;
    api.request<Page<Relationship>>(`/api/v1/professional/patient-relationships?organization_id=${encodeURIComponent(organizationId)}`).then(page => {
      if (!live) return;
      const active = (Array.isArray(page?.items) ? page.items : []).filter(r => r.state === 'active');
      setMore(active.length > MAX_CONVERSATIONS || !!page?.next_cursor);
      setRoster(active.slice(0, MAX_CONVERSATIONS).map(r => ({ id: r.id, title: `Patient · ${shortId(r.patient_uid)}`, counterpart: r.patient_uid })));
    }).catch(e => { if (live) { setRosterError(true); if (stops(e)) fail(e); } });
    return () => { live = false; };
  }, [api, role, organizationId, patientRelationships, fail]);

  const refresh = useCallback(async (id: string) => {
    try {
      const result = await loadThread(api, id);
      if (!alive.current) return;
      setThreads(old => ({ ...old, [id]: { messages: mergeMessages(old[id]?.messages ?? [], result.messages), capped: result.capped, loaded: true } }));
    } catch (e) {
      if (!alive.current) return;
      if (stops(e)) { fail(e); throw e; }
      setThreads(old => ({ ...old, [id]: { messages: old[id]?.messages ?? [], capped: old[id]?.capped ?? false, loaded: true, error: 'Could not refresh this conversation. Retrying shortly.' } }));
      throw e;
    }
  }, [api, fail]);

  // Previews: each conversation is read once when the list opens (one at a time), not polled.
  useEffect(() => {
    if (!roster) return;
    let live = true;
    (async () => { for (const c of roster) { if (!live) return; if (requested.current.has(c.id)) continue; requested.current.add(c.id); try { await refresh(c.id); } catch (e) { if (stops(e)) return; } } })();
    return () => { live = false; };
  }, [roster, refresh]);

  // Open conversation: polled while visible, and registered so the notifier knows which notices are already on screen.
  useEffect(() => {
    if (!openId) return;
    const id = openId;
    unreadStore.activeChat = { hasMessage: m => !!threadsRef.current[id]?.messages.some(x => x.id === m), refresh: () => refresh(id).catch(() => undefined) };
    const poller = createPoller({ intervalMs: messagePollMs(), run: () => refresh(id), isFatal: stops });
    poller.start();
    return () => { poller.stop(); unreadStore.activeChat = null; };
  }, [openId, refresh]);

  // Mark the open conversation's notices read once its messages are loaded (sequential, capped in the store).
  const open = roster?.find(c => c.id === openId), openThread = openId ? threads[openId] : undefined;
  useEffect(() => {
    if (!openThread?.loaded || document.hidden) return;
    const ids = unreadForThread(unread.notices, openThread.messages).map(n => n.id).filter(id => !requested.current.has(`read:${id}`));
    if (!ids.length) return;
    ids.forEach(id => requested.current.add(`read:${id}`));
    void unreadStore.markRead?.(ids);
  }, [unread.notices, openThread]);

  // A notice that matches no loaded message means a new message in a conversation we have not read yet: refresh the previews once.
  useEffect(() => {
    if (!roster?.length) return;
    const all = new Set(Object.values(threads).flatMap(t => t.messages.map(m => m.id)));
    const fresh = unreadMessageNotices(unread.notices).filter(n => !all.has(noticeMessageId(n)) && !attempted.current.has(n.id));
    if (!fresh.length) return;
    fresh.forEach(n => attempted.current.add(n.id));
    (async () => { for (const c of roster) { if (c.id === openId) continue; try { await refresh(c.id); } catch (e) { if (stops(e)) return; } } })();
  }, [unread.notices, roster, openId, threads, refresh]);

  if (roster === null) return <p role="status"><span className="neo-spinner" aria-hidden="true" /> Loading conversations…</p>;
  const now = new Date();
  const list = <nav aria-label="Conversations" className={`${open ? 'hidden md:block' : ''}`}>
    <h2 style={{ fontSize: '1.1rem' }}>Messages</h2>
    {rosterError && <p role="alert" className="professional-error">Could not load your conversations. Refresh the page to try again.</p>}
    {!roster.length && !rosterError && <p>{role === 'patient' ? 'No conversations yet. Messages appear once a psychologist accepts you.' : 'No active patients yet. Messages appear once a patient is connected to your practice.'}</p>}
    <ul className="professional-stack" style={{ listStyle: 'none', padding: 0 }}>
      {roster.map(c => {
        const t = threads[c.id], last = t?.messages[t.messages.length - 1], count = t ? unreadForThread(unread.notices, t.messages).length : 0;
        return <li key={c.id}><button type="button" aria-current={c.id === openId ? 'true' : undefined} onClick={() => setOpenId(c.id)} className="w-full text-left border-[3px] border-black rounded-xl p-3 bg-white" style={{ display: 'block', width: '100%', textAlign: 'start' }}>
          <span style={{ display: 'flex', justifyContent: 'space-between', gap: 8 }}><strong>{c.title}</strong>{last && <span className="professional-muted" style={{ fontSize: '.75rem' }}>{dayLabel(last.created_at, now) === 'Today' ? timeLabel(last.created_at) : dayLabel(last.created_at, now)}</span>}</span>
          <span style={{ display: 'flex', justifyContent: 'space-between', gap: 8 }}><span dir="auto" className="professional-muted" style={{ fontSize: '.85rem' }}>{last ? preview(last.body) : t?.loaded ? 'No messages yet' : 'Loading…'}</span>
            {count > 0 && <span className="professional-badge" aria-label={`${count} unread`}>{badgeText(count)}</span>}</span>
        </button></li>;
      })}
    </ul>
    {more && <p className="professional-muted" style={{ fontSize: '.75rem' }}>Showing the first {MAX_CONVERSATIONS} conversations.</p>}
    <DesktopToggle />
  </nav>;
  return <div className="md:grid md:grid-cols-[320px_1fr] md:gap-4">{list}
    {open ? <ChatPane key={open.id} api={api} conversation={open} messages={openThread?.messages ?? []} capped={!!openThread?.capped} loaded={!!openThread?.loaded} error={openThread?.error}
      onSent={m => setThreads(old => ({ ...old, [open.id]: { messages: mergeMessages(old[open.id]?.messages ?? [], [m]), capped: old[open.id]?.capped ?? false, loaded: true } }))}
      onBack={() => setOpenId(null)} onError={fail} />
      : <div className="hidden md:flex items-center justify-center professional-muted" style={{ minHeight: 200 }}><p>Select a conversation.</p></div>}
  </div>;
}
