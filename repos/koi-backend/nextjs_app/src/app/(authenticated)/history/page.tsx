'use client';
import { useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { useAuth } from '@/contexts/AuthContext';
import { auth } from '@/lib/firebase';
import { useSharedConversation } from '@/contexts/ConversationContext';
import { readOwnedHistory, searchHistory, HISTORY_MESSAGE_LIMIT, HistoryReadError, type HistoryResult } from '@/lib/history/readHistory';

type View = { owner: string; status: 'loading' | 'locked' | 'error' } | { owner: string; status: 'ready'; data: HistoryResult };
export default function HistoryPage() {
  const { user, isLinked } = useAuth();
  const manager = useSharedConversation();
  const [view, setView] = useState<View | null>(null);
  const [query, setQuery] = useState('');
  const [selected, setSelected] = useState<string | null>(null);
  const [revision, refresh] = useState(0);
  const ownerRef = useRef(user?.uid); ownerRef.current = user?.uid;
  useEffect(() => {
    if (!user) return;
    const owner = user.uid, controller = new AbortController();
    const current = () => !controller.signal.aborted && ownerRef.current === owner && auth?.currentUser?.uid === owner;
    setView({ owner, status: 'loading' }); setQuery(''); setSelected(null);
    void (async () => {
      try {
        if (!current()) return;
        if (manager.uid !== owner || !manager.session) throw new HistoryReadError('locked');
        // Reuse only P0's already unlocked transcript; never generate or retrieve raw keys.
        const session = manager.session;
        const data = await readOwnedHistory(owner, async (_ciphertext, record) => {
          const message = session.getSnapshot().messages.find(m => m.id === record.id && m.conversationId === record.conversationId);
          if (!message) throw new HistoryReadError('locked');
          return message.content;
        }, { signal: controller.signal, isCurrentOwner: current, allowLockedMetadata: true });
        if (current()) setView({ owner, status: 'ready', data });
      } catch (error) { if (current()) setView({ owner, status: error instanceof HistoryReadError ? 'locked' : 'error' }); }
    })();
    return () => controller.abort();
  }, [user?.uid, isLinked, revision, manager]);
  const state = view?.owner === user?.uid ? view : null;
  const data = state?.status === 'ready' ? state.data : null;
  const filtered = data ? searchHistory(data, query) : [];
  const conversation = data?.conversations.find(c => c.id === selected);
  return <div className="max-w-3xl mx-auto p-6">
    <Link href="/chat" className="underline">Back to current chat</Link>
    <h1 className="text-3xl font-black my-5">Conversation history</h1>
    <p className="text-sm mb-4">Device-local, encrypted saved messages. Titles quote retained user input, not AI summaries. Search covers at most the newest {HISTORY_MESSAGE_LIMIT} retained messages. Nothing is deleted or sent to a search service.</p>
    <p className="text-sm mb-4">The current conversation uses P0’s already unlocked transcript. Other retained conversations stay locked until the read-only unlocking interface is reviewed. Locked message bodies are not searched.</p>
    {!state || state.status === 'loading' ? <p role="status">Unlocking saved history…</p> : state.status === 'locked' || state.status === 'error' ? <div role="alert">
      <p>{state.status === 'locked' ? 'History could not be unlocked on this device. Linked-account unlocking may require the approved account recovery flow.' : 'Saved history could not be read. Check browser storage access and retry.'} No records were changed.</p>
      <button className="neo-btn-ghost mt-3" onClick={() => refresh(n => n + 1)}>Retry history</button>
    </div> : <>
      <label className="block mb-4">Search retained messages
        <input className="neo-input block w-full mt-2" type="search" maxLength={120} value={query} onChange={e => setQuery(e.target.value)} />
      </label>
      <button className="neo-btn-ghost mb-4" onClick={() => refresh(n => n + 1)}>Refresh saved history</button>
      {data?.truncated && <p role="status">Showing only the newest {HISTORY_MESSAGE_LIMIT} retained messages. Older records were not searched.</p>}
      {!!data?.unreadable && <p role="status">Some retained records could not be unlocked or validated and are not displayed.</p>}
      {!filtered.length && <p role="status">{query ? 'No matching retained messages.' : 'No saved conversation messages yet.'}</p>}
      <ul className="space-y-4">{filtered.map(c => <li key={c.id} className="neo-card p-5">
        <h2 className="font-bold" dir="auto">{c.title || (c.messages.length ? 'Untitled conversation' : 'Locked conversation')}</h2>
        <p className="text-sm">{c.createdAt ? 'Created' : 'Earliest retained message'}: {(c.createdAt ?? c.earliestRetainedAt).toLocaleString()}</p>
        <p className="text-sm">Last saved message: {c.lastActivityAt.toLocaleString()} · {c.retainedRecords} retained records · {c.messages.length} readable messages</p>
        <button className="neo-btn-ghost mt-3" disabled={!c.messages.length} aria-expanded={selected === c.id} onClick={() => setSelected(selected === c.id ? null : c.id)}>Read saved conversation</button>
        {c.active ? <Link className="underline block mt-3" href="/chat">Continue current conversation</Link>
          : <p className="text-sm mt-3">Read-only: switching into this saved conversation awaits the shared session selector. Your current chat remains active.</p>}
      </li>)}</ul>
      {conversation && <section className="neo-card p-5 mt-5" aria-label="Saved conversation transcript">
        <h2 className="font-bold mb-3">Saved transcript</h2>
        {conversation.messages.map(m => <article className="mb-4" key={m.id}><p className="font-bold">{m.sender === 'user' ? 'You' : 'KOI'} · {m.at.toLocaleString()}</p><p className="whitespace-pre-wrap break-words" dir="auto">{m.text}</p></article>)}
      </section>}
    </>}
  </div>;
}
