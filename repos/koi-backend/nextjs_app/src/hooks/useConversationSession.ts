'use client';
import { useEffect, useState, useSyncExternalStore } from 'react';
import { ConversationSession, type SessionMessage } from '../lib/conversation/ConversationSession';
import type { ChatAdapter } from '../lib/conversation/chatContract';
export function useConversationSession(adapter: ChatAdapter, initialMessages: SessionMessage[] = [], shared?: ConversationSession) {
  const [local] = useState(() => shared ?? new ConversationSession(adapter, undefined, initialMessages));
  const session = shared ?? local;
  const snapshot = useSyncExternalStore(session.subscribe, session.getSnapshot, session.getSnapshot);
  useEffect(() => { if (!shared) { session.activate(); return () => session.deactivate(); } }, [session, shared]);
  return { ...snapshot, session, send: (text: string) => session.send(text), cancel: () => session.cancel() };
}
