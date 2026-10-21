'use client';
import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import NeoButton from '@/components/ui/NeoButton';
import type { ProfessionalApi } from '@/lib/platform/client';
import type { HumanMessage } from '@/lib/platform/community-types';
import { MAX_THREAD_MESSAGES, MESSAGE_LIMIT, bodyLength, canSend, dayKey, dayLabel, sortMessages, timeLabel } from '@/lib/platform/messaging/model';

export interface Conversation { id: string; title: string; counterpart: string }
interface Outgoing { localId: string; body: string; created_at: string; status: 'sending' | 'failed' }
type Row = { key: string; created_at: string; body: string; mine: boolean; state: 'sent' | 'sending' | 'failed'; localId?: string };
const status = (e: unknown) => (e as { status?: number } | null)?.status;
let counter = 0;

export default function ChatPane({ api, conversation, messages, capped, loaded, error, onSent, onBack, onError }: {
  api: Pick<ProfessionalApi, 'request'>; conversation: Conversation; messages: HumanMessage[]; capped: boolean; loaded: boolean; error?: string;
  onSent: (message: HumanMessage) => void; onBack: () => void; onError: (error: unknown) => void;
}) {
  const [draft, setDraft] = useState(''), [outbox, setOutbox] = useState<Outgoing[]>([]), [jump, setJump] = useState(false);
  const box = useRef<Outgoing[]>([]), flushing = useRef(false), alive = useRef(true), scroller = useRef<HTMLDivElement>(null), stick = useRef(true), seen = useRef(0);
  useEffect(() => { alive.current = true; return () => { alive.current = false; }; }, []);
  const change = (fn: (old: Outgoing[]) => Outgoing[]) => { box.current = fn(box.current); if (alive.current) setOutbox(box.current); };
  /** One request at a time: the client derives the Idempotency-Key from method+path+body, so identical texts must never overlap. */
  const flush = async () => {
    if (flushing.current) return; flushing.current = true;
    try {
      for (;;) {
        const next = box.current.find(o => o.status === 'sending'); if (!next) break;
        try {
          const sent = await api.request<HumanMessage>('/api/v1/messages', 'POST', { relationship_id: conversation.id, body: next.body });
          change(old => old.filter(o => o.localId !== next.localId)); onSent(sent);
        } catch (e) {
          change(old => old.map(o => o.localId === next.localId ? { ...o, status: 'failed' } : o));
          if (status(e) === 403 || status(e) === 404) { onError(e); break; }
        }
      }
    } finally { flushing.current = false; }
  };
  const send = () => {
    if (!canSend(draft)) return;
    const item: Outgoing = { localId: `local-${++counter}`, body: draft, created_at: new Date().toISOString(), status: 'sending' };
    change(old => [...old, item]); setDraft(''); stick.current = true; void flush();
  };
  const retry = (localId: string) => { change(old => old.map(o => o.localId === localId ? { ...o, status: 'sending' } : o)); void flush(); };

  const rows: Row[] = [
    ...sortMessages(messages).map(m => ({ key: m.id, created_at: m.created_at, body: m.body, mine: m.sender_uid !== conversation.counterpart, state: 'sent' as const })),
    ...outbox.map(o => ({ key: o.localId, created_at: o.created_at, body: o.body, mine: true, state: o.status, localId: o.localId })),
  ];
  const onScroll = () => { const el = scroller.current; if (!el) return; stick.current = el.scrollHeight - el.scrollTop - el.clientHeight < 48; if (stick.current) setJump(false); };
  const toBottom = () => { const el = scroller.current; if (el) el.scrollTop = el.scrollHeight; stick.current = true; setJump(false); };
  useLayoutEffect(() => {
    const grew = rows.length > seen.current && seen.current > 0, lastMine = rows[rows.length - 1]?.mine;
    if (stick.current || lastMine) toBottom(); else if (grew) setJump(true);
    seen.current = rows.length;
  }, [rows.length]);

  const length = bodyLength(draft), over = length > MESSAGE_LIMIT, now = new Date();
  let lastDay = '';
  return <section aria-label={`Conversation with ${conversation.title}`} className="flex flex-col min-h-[60vh] border-[3px] border-black rounded-2xl bg-white overflow-hidden">
    <header className="flex items-center gap-2 p-3 border-b-[3px] border-black">
      <button type="button" className="neo-btn-ghost md:hidden" onClick={onBack} aria-label="Back to conversations">←</button>
      <div><h2 style={{ fontSize: '1.1rem' }}>{conversation.title}</h2><p className="professional-muted" style={{ fontSize: '.75rem' }}>A human conversation, separate from your KOI companion. Not an emergency service.</p></div>
    </header>
    <div ref={scroller} onScroll={onScroll} className="flex-1 overflow-y-auto p-3 relative" style={{ maxHeight: '60vh' }}>
      {!loaded && <p role="status"><span className="neo-spinner" aria-hidden="true" /> Loading messages…</p>}
      {loaded && !rows.length && <p>No messages yet. Say hello below.</p>}
      {capped && <p className="professional-muted" role="note">Showing {MAX_THREAD_MESSAGES} messages. This view is limited to {MAX_THREAD_MESSAGES}, so some messages may not appear.</p>}
      <div role="log" aria-live="polite" aria-relevant="additions" aria-label="Messages">
        {rows.map(r => {
          const key = dayKey(r.created_at), separator = key !== lastDay ? <p className="professional-muted" style={{ textAlign: 'center', fontSize: '.75rem', margin: '.75rem 0' }} data-testid="day-separator">{dayLabel(r.created_at, now)}</p> : null;
          lastDay = key;
          return <div key={r.key}>{separator}
            <div style={{ display: 'flex', justifyContent: r.mine ? 'flex-end' : 'flex-start', margin: '.25rem 0' }}>
              <div className={r.mine ? 'bg-[#e0f2fe]' : 'bg-[#f4f4f5]'} style={{ maxWidth: '80%', border: '2px solid #000', borderRadius: 12, padding: '.4rem .6rem' }}>
                <p dir="auto" style={{ whiteSpace: 'pre-wrap', overflowWrap: 'anywhere', margin: 0 }}>{r.body}</p>
                <p style={{ fontSize: '.7rem', margin: 0, textAlign: 'end' }}><time dateTime={r.created_at}>{timeLabel(r.created_at)}</time>
                  {r.mine && (r.state === 'sent' ? ' · Sent' : r.state === 'sending' ? ' · Sending...' : null)}
                  {r.state === 'failed' && <> · <button type="button" className="underline" onClick={() => retry(r.localId!)}>Not sent. Tap to retry</button></>}</p>
              </div>
            </div>
          </div>;
        })}
      </div>
    </div>
    {error && <p role="alert" className="professional-error" style={{ padding: '0 .75rem' }}>{error}</p>}
    {jump && <div style={{ textAlign: 'center' }}><NeoButton variant="secondary" onClick={toBottom}>New messages</NeoButton></div>}
    <form className="flex items-end gap-2 p-3 border-t-[3px] border-black" onSubmit={e => { e.preventDefault(); send(); }}>
      <div style={{ flex: 1 }}>
        <textarea className="neo-input" aria-label="Message" aria-describedby="message-counter" rows={2} dir="auto" value={draft} placeholder="Write a message" style={{ width: '100%' }}
          onChange={e => setDraft(e.target.value)}
          onKeyDown={e => { if (e.key === 'Enter' && !e.shiftKey && !e.nativeEvent.isComposing) { e.preventDefault(); send(); } }} />
        <p id="message-counter" className={over ? 'professional-error' : 'professional-muted'} style={{ fontSize: '.75rem', margin: 0 }} role={over ? 'alert' : undefined}>
          {over ? `Too long: ${length}/${MESSAGE_LIMIT}` : length >= MESSAGE_LIMIT - 400 ? `${length}/${MESSAGE_LIMIT}` : 'Enter to send, Shift+Enter for a new line'}</p>
      </div>
      <NeoButton type="submit" disabled={!canSend(draft)}>Send</NeoButton>
    </form>
  </section>;
}
