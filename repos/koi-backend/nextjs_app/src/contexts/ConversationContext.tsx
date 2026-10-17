"use client";
import { createContext, useContext, useEffect, useState, useRef, useSyncExternalStore } from 'react';
import { useAuth } from './AuthContext';
import { PersistentConversation } from '@/lib/conversation/PersistentConversation';
import { sendMessage } from '@/lib/conversation/conversationService';
import type { ChatAdapter } from '@/lib/conversation/chatContract';

const Context = createContext<PersistentConversation | null>(null);
export const useSharedConversation = () => {
  const value = useContext(Context);
  if (!value) throw new Error('useChat requires ConversationProvider');
  return value;
};
export default function ConversationProvider({ children }: { children: React.ReactNode }) {
  const { user, isLinked } = useAuth();
  if (!user) return null;
  return <OwnedConversation key={`${user.uid}:${isLinked}`} uid={user.uid} isLinked={isLinked}>{children}</OwnedConversation>;
}
function OwnedConversation({ uid, isLinked, children }: { uid: string; isLinked: boolean; children: React.ReactNode }) {
  const [manager] = useState(() => {
    const adapter: ChatAdapter = { send: (request, options) => sendMessage(uid, manager.session!.conversationId,
      request.message, request.session_history, { isLinked }, options, {
        exercise_state: request.exercise_state, client_event: request.client_event,
        policy_event: request.policy_event, crisis_path: request.crisis_path,
      }) };
    return new PersistentConversation(uid, adapter, { isLinked });
  });
  const state = useSyncExternalStore(manager.subscribe, manager.getSnapshot, manager.getSnapshot);
  const generation = useRef(0);
  useEffect(() => {
    const lease = ++generation.current;
    // Deferral avoids starting two owners during React StrictMode's effect probe.
    let mounted = true;
    const start = setTimeout(() => { if (mounted) void manager.initialize(); }, 0);
    return () => { mounted = false; clearTimeout(start); queueMicrotask(() => { if (generation.current === lease) manager.dispose(); }); };
  }, [manager]);
  return <Context.Provider value={manager}>{state.loading || !manager.session
    ? <div role="status" style={{ padding: 24 }}>{state.error ?? 'Restoring encrypted conversation...'}</div>
    : children}</Context.Provider>;
}
