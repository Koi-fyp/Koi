"use client";
import { useSyncExternalStore } from 'react';
import { useSharedConversation } from '@/contexts/ConversationContext';
import { useConversationSession } from './useConversationSession';
import type { SessionMessage } from '@/lib/conversation/ConversationSession';
import type { KoiEmotion } from '@/components/avatar/VRMAvatarController';
export interface ChatMessage extends SessionMessage { emotion: KoiEmotion; }
export function useChat() {
  const manager = useSharedConversation();
  const recovery = useSyncExternalStore(manager.subscribe, manager.getSnapshot, manager.getSnapshot);
  const session = manager.session!;
  const chat = useConversationSession({ send: async () => { throw new Error('Shared session required'); } }, [], session);
  const messages: ChatMessage[] = chat.messages
    .filter(m => !(m.sender === 'ai' && m.status === 'pending' && !m.content))
    .map(m => ({ ...m, emotion: m.companion_state?.emotion ?? 'neutral' }));
  return { ...chat, messages, isTyping: chat.pending, currentEmotion: chat.companion.emotion,
    currentIntensity: chat.companion.intensity, conversationId: session.conversationId,
    blocked: recovery.loading || !!recovery.error, error: recovery.error ?? chat.error };
}
