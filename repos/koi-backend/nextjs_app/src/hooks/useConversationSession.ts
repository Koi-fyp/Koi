'use client';
import { useEffect, useState, useSyncExternalStore } from 'react';
import { ConversationSession, type SessionMessage } from '../lib/conversation/ConversationSession';
import type { ChatAdapter } from '../lib/conversation/chatContract';
export function useConversationSession(adapter: ChatAdapter, initialMessages: SessionMessage[] = []) {
  const [session] = useState(() => new ConversationSession(adapter, undefined, initialMessages));
  const snapshot = useSyncExternalStore(session.subscribe, session.getSnapshot, session.getSnapshot);
  useEffect(() => { session.activate(); return () => session.deactivate(); }, [session]);
  return { ...snapshot, session, send: (text: string) => session.send(text), cancel: () => session.cancel() };
}
