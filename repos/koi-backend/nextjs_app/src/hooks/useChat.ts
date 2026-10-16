'use client';
import { useEffect, useRef, useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { db } from '@/lib/db';
import { decrypt, getActiveCryptoContext, type AuthState } from '@/lib/crypto';
import { sendMessage } from '@/lib/conversation/conversationService';
import { ChatError, type ChatAdapter, type CompanionState } from '@/lib/conversation/chatContract';
import { useConversationSession } from './useConversationSession';
import type { SessionMessage } from '@/lib/conversation/ConversationSession';
import type { KoiEmotion } from '@/components/avatar/VRMAvatarController';
export interface ChatMessage extends SessionMessage { emotion: KoiEmotion; }
export function useChat({ linkedSecret }: { linkedSecret?: string } = {}) {
  const { user, isLinked } = useAuth();
  const current = useRef({ user, isLinked, linkedSecret }); current.current = { user, isLinked, linkedSecret };
  const owner = useRef<string | null>(user?.uid ?? null);
  if (!owner.current && user) owner.current = user.uid;
  const [readError, setReadError] = useState<string | null>(null);
  const sessionId = useRef<string | null>(null);
  const [adapter] = useState<ChatAdapter>(() => ({ send: async (request, options) => {
    const account = current.current;
    if (!account.user || account.user.uid !== owner.current) throw new ChatError('authentication', 'An authenticated, unchanged KOI session is required.');
    const authState: AuthState = { isLinked: account.isLinked, linkedSecret: account.linkedSecret };
    return sendMessage(account.user.uid, sessionId.current!, request.message, request.session_history, authState, options, {
      exercise_state: request.exercise_state,
      client_event: request.client_event,
      policy_event: request.policy_event,
      crisis_path: request.crisis_path,
    });
  } }));
  const chat = useConversationSession(adapter); sessionId.current = chat.session.conversationId;
  useEffect(() => {
    if (!user || user.uid !== owner.current) return;
    let cancelled = false; const versionMessages = chat.session.getSnapshot().messages;
    setReadError(null);
    void (async () => {
      const rows = await db.messages.where('conversationId').equals(chat.session.conversationId).sortBy('timestamp');
      if (!rows.length) return;
      const { secret } = await getActiveCryptoContext(user.uid, { isLinked, linkedSecret });
      const messages: SessionMessage[] = await Promise.all(rows.map(async (row) => {
        const legacy: CompanionState = { emotion: row.emotion === 'happy' ? 'joy' : row.emotion === 'sad' ? 'sorrow' : 'neutral', intensity: row.emotion === 'happy' || row.emotion === 'sad' ? 0.5 : 0 };
        return { id: row.id, conversationId: row.conversationId, sender: row.sender, content: await decrypt(row.content, secret),
          timestamp: row.timestamp, status: 'completed', companion_state: row.companion_state ?? legacy };
      }));
      if (!cancelled && chat.session.getSnapshot().messages === versionMessages) chat.session.replaceMessages(messages);
    })().catch(() => { if (!cancelled) setReadError(isLinked && !linkedSecret ? 'Unlock your linked account before chatting.' : 'Conversation storage could not be unlocked.'); });
    return () => { cancelled = true; chat.cancel(); };
  }, [user?.uid, isLinked, linkedSecret, chat.session]);
  const accountChanged = owner.current !== null && user?.uid !== owner.current;
  const messages: ChatMessage[] = (accountChanged ? [] : chat.messages)
    .filter((message) => !(message.sender === 'ai' && message.status === 'pending' && !message.content))
    .map((message) => ({ ...message, emotion: message.companion_state?.emotion ?? 'neutral' }));
  return { ...chat, messages, subtitle: accountChanged ? '' : chat.subtitle, isTyping: chat.pending, currentEmotion: accountChanged ? 'neutral' as const : chat.companion.emotion,
    currentIntensity: accountChanged ? 0 : chat.companion.intensity, conversationId: chat.session.conversationId,
    blocked: accountChanged || !user || (isLinked && !linkedSecret), error: accountChanged ? 'Your account changed. Start a new chat session.' : chat.error ?? (isLinked && !linkedSecret ? 'Unlock your linked account before chatting.' : readError) };
}
