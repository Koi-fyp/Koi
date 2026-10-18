'use client';
import { useEffect, useRef, useState, useSyncExternalStore } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/contexts/AuthContext';
import { auth } from '@/lib/firebase';
import { useOwnedConversationActions, useSharedConversation } from '@/contexts/ConversationContext';
import { ConversationSwitchError } from '@/lib/conversation/PersistentConversation';
import { readOwnedHistory, searchHistory, HISTORY_MESSAGE_LIMIT, HistoryReadError, type HistoryConversation, type HistoryResult } from '@/lib/history/readHistory';
import { readArchivedConversations, ARCHIVE_LIST_LIMIT } from '@/lib/history/readArchive';

type Listed = HistoryConversation & { source: 'active' | 'archived' | 'retained'; locked: boolean };
type Data = Omit<HistoryResult, 'conversations'> & { conversations: Listed[] };
type View = { owner: string; status: 'loading' | 'locked' | 'error' } | { owner: string; status: 'ready'; data: Data };
const SWITCH_MESSAGES: Record<string, string> = {
  busy: 'A reply is in progress. Wait for it to finish, then try again.',
  'crisis-open': 'Please finish the safety check first.',
  conflict: 'This conversation changed in another tab. Reload this page; nothing was changed here.',
  'owner-changed': 'Your account changed. Nothing was changed.',
  'not-found': 'That saved conversation is no longer available.',
  locked: 'That saved conversation cannot be unlocked on this device.',
  'storage-unavailable': 'Browser storage is unavailable. Nothing was changed; please retry.',
};
const switchMessage = (error: unknown) => SWITCH_MESSAGES[error instanceof ConversationSwitchError ? error.reason : 'storage-unavailable'];

export default function HistoryPage() {
  const { user, isLinked } = useAuth();
  const manager = useSharedConversation();
  const { createOwned, openOwned } = useOwnedConversationActions();
  const router = useRouter();
  const recovery = useSyncExternalStore(manager.subscribe, manager.getSnapshot, manager.getSnapshot);
  const session = manager.session!;
  const current = useSyncExternalStore(session.subscribe, session.getSnapshot, session.getSnapshot);
  const pending = current.pending;
  const [view, setView] = useState<View | null>(null);
  const [query, setQuery] = useState('');
  const [selected, setSelected] = useState<string | null>(null);
  const [revision, refresh] = useState(0);
  const [actionError, setActionError] = useState<string | null>(null);
  const [acting, setActing] = useState(false);
  const ownerRef = useRef(user?.uid); ownerRef.current = user?.uid;
  useEffect(() => {
    if (!user) return;
    const owner = user.uid, controller = new AbortController();
    const isCurrent = () => !controller.signal.aborted && ownerRef.current === owner && auth?.currentUser?.uid === owner;
    setView({ owner, status: 'loading' }); setQuery(''); setSelected(null);
    void (async () => {
      try {
        if (!isCurrent()) return;
        if (manager.uid !== owner || !manager.session) throw new HistoryReadError('locked');
        const active = manager.session, header = manager.getActiveHeader();
        // Retained rows: only P0's already unlocked transcript decrypts them; other groups stay locked/read-only.
        const retained = await readOwnedHistory(owner, async (_ciphertext, record) => {
          const message = active.getSnapshot().messages.find(m => m.id === record.id && m.conversationId === record.conversationId);
          if (!message) throw new HistoryReadError('locked');
          return message.content;
        }, { signal: controller.signal, isCurrentOwner: isCurrent, allowLockedMetadata: true });
        const archive = await readArchivedConversations(owner, controller.signal);
        if (!isCurrent()) return;
        if (archive.status === 'unavailable') throw new Error('Archive unavailable');
        const messages = active.getSnapshot().messages.filter(m => m.content);
        const listed: Listed[] = [{ id: active.conversationId, source: 'active', locked: false,
          title: messages.find(m => m.sender === 'user' && m.content.trim())?.content.trim().slice(0, 80) ?? '',
          createdAt: header?.createdAt ?? null, earliestRetainedAt: messages[0]?.timestamp ?? header?.createdAt ?? new Date(),
          lastActivityAt: messages[messages.length - 1]?.timestamp ?? header?.lastActiveAt ?? new Date(), active: true,
          retainedRecords: messages.length, messages: messages.map(m => ({ id: m.id, sender: m.sender, text: m.content, at: m.timestamp })) }];
        for (const c of archive.conversations) listed.push({ id: c.conversationId, source: 'archived', locked: c.locked, title: c.title,
          createdAt: c.createdAt, earliestRetainedAt: c.createdAt, lastActivityAt: c.lastActiveAt, active: false,
          retainedRecords: c.messageCount ?? 0, messages: c.messages });
        const known = new Set(listed.map(c => c.id));
        for (const c of retained.conversations) if (!known.has(c.id)) listed.push({ ...c, source: 'retained', locked: !c.messages.length });
        // Rows of the active or archived conversations are listed from their headers, not counted as unreadable.
        const listedUnreadable = retained.conversations.filter(c => known.has(c.id)).reduce((sum, c) => sum + c.retainedRecords - c.messages.length, 0);
        setView({ owner, status: 'ready', data: { ...retained, unreadable: Math.max(0, retained.unreadable - listedUnreadable), truncated: retained.truncated || archive.truncated,
          conversations: [listed[0], ...listed.slice(1).sort((a, b) => +b.lastActivityAt - +a.lastActivityAt)] } });
      } catch (error) { if (isCurrent()) setView({ owner, status: error instanceof HistoryReadError ? 'locked' : 'error' }); }
    })();
    return () => controller.abort();
  }, [user?.uid, isLinked, revision, manager]);
  const act = async (action: () => Promise<unknown>) => {
    const owner = user?.uid;
    setActionError(null); setActing(true);
    try { await action(); if (auth?.currentUser?.uid === owner) router.push('/chat'); }
    catch (error) { if (auth?.currentUser?.uid === owner) setActionError(switchMessage(error)); }
    finally { setActing(false); }
  };
  const busy = pending || acting || recovery.switching || recovery.completing || !!recovery.error;
  // Only the current conversation stays reachable while its safety check is open.
  const crisisOpen = recovery.hasUnresolvedHandoff;
  const state = view?.owner === user?.uid ? view : null;
  const data = state?.status === 'ready' ? state.data : null;
  const filtered = data ? searchHistory(data, query) as Listed[] : [];
  const conversation = data?.conversations.find(c => c.id === selected);
  return <div className="max-w-3xl mx-auto p-6">
    <Link href="/chat" className="neo-btn-secondary neo-btn-sm">Back to current chat</Link>
    <h1 className="text-3xl font-black my-5">Conversation history</h1>
    <button type="button" disabled={busy || crisisOpen} onClick={() => void act(createOwned)} className="neo-btn-primary mb-3" aria-describedby="history-create-status">{pending ? 'New Chat (reply in progress)' : 'New Chat'}</button>
    {crisisOpen && <p className="text-sm mb-2 font-bold">Please finish the safety check first.</p>}
    <p id="history-create-status" className="text-sm mb-4">New Chat saves the current conversation here and starts a separate one. It does not complete the conversation or award a piece.</p>
    {actionError && <p role="alert" className="mb-4">{actionError}</p>}
    <p className="text-sm mb-4">Device-local, encrypted conversations. Titles quote your first saved message, not AI summaries. Up to {ARCHIVE_LIST_LIMIT} saved conversations and the newest {HISTORY_MESSAGE_LIMIT} retained messages are listed. No records are deleted.</p>
    <p className="text-sm mb-4">Saved conversations unlock only with the key already on this device. Conversations that cannot be unlocked show as locked and stay unchanged. Locked message bodies are not searched.</p>
    {!state || state.status === 'loading' ? <p role="status">Unlocking saved history…</p> : state.status === 'locked' || state.status === 'error' ? <div role="alert">
      <p>{state.status === 'locked' ? 'History could not be unlocked on this device. Linked-account unlocking may require the approved account recovery flow.' : 'Saved history could not be read. Check browser storage access and retry.'} No records were changed.</p>
      <button className="neo-btn-secondary neo-btn-sm mt-3" onClick={() => refresh(n => n + 1)}>Retry history</button>
    </div> : <>
      <details className="mb-4"><summary className="cursor-pointer">Optional message search</summary><label className="block mt-3">Search retained messages
        <input className="neo-input block w-full mt-2" type="search" maxLength={120} value={query} onChange={e => setQuery(e.target.value)} />
      </label><p className="text-sm">Search stays on this device and only covers readable messages.</p></details>
      <button className="neo-btn-secondary neo-btn-sm mb-4" onClick={() => refresh(n => n + 1)}>Refresh saved history</button>
      {data?.truncated && <p role="status">This is a bounded history view. Older conversations or messages outside it were not searched or deleted.</p>}
      {!!data?.unreadable && <p role="status">Some retained records could not be unlocked or validated and are not displayed.</p>}
      {!filtered.length && <p role="status">{query ? 'No matching retained messages.' : 'No saved conversation messages yet.'}</p>}
      <ul className="space-y-4">{filtered.map(c => <li key={c.id} className="neo-card p-5">
        <h2 className="font-bold" dir="auto">{c.title || (c.locked ? 'Locked conversation' : c.messages.length ? 'Untitled conversation' : 'Empty conversation')}</h2>
        <p className="text-sm font-bold">{c.active ? 'Current conversation' : 'Saved conversation'}{c.locked ? ' · Locked' : ''}</p>
        <p className="text-sm">{c.createdAt ? 'Created' : 'Earliest retained message'}: {(c.createdAt ?? c.earliestRetainedAt).toLocaleString()}</p>
        <p className="text-sm">Last activity: {c.lastActivityAt.toLocaleString()} · {c.locked ? 'message count locked' : `${c.messages.length} messages`}</p>
        <div className="koi-action-row mt-3">
        <button className="neo-btn-secondary neo-btn-sm" disabled={!c.messages.length} aria-expanded={selected === c.id} onClick={() => setSelected(selected === c.id ? null : c.id)}>Read saved conversation</button>
        {c.active ? <Link className="neo-btn-primary neo-btn-sm" href="/chat">Continue current conversation</Link>
          : c.source === 'archived' && !c.locked ? <button type="button" className="neo-btn-primary neo-btn-sm" disabled={busy || crisisOpen} onClick={() => void act(() => openOwned(c.id))}>{pending ? 'Open conversation (reply in progress)' : 'Open conversation'}</button>
          : <p className="text-sm">{c.locked ? 'This conversation is locked on this device and cannot be opened. It remains unchanged.' : 'This retained conversation is read-only. It remains unchanged.'}</p>}
        </div>
      </li>)}</ul>
      {conversation && <section className="neo-card p-5 mt-5" aria-label="Saved conversation transcript">
        <h2 className="font-bold mb-3">Saved transcript</h2>
        {conversation.messages.map(m => <article className="mb-4" key={m.id}><p className="font-bold">{m.sender === 'user' ? 'You' : 'KOI'} · {m.at.toLocaleString()}</p><p className="whitespace-pre-wrap break-words" dir="auto">{m.text}</p></article>)}
      </section>}
    </>}
  </div>;
}
