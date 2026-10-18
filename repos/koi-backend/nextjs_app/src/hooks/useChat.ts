"use client";
import { useSyncExternalStore } from 'react';
import { useSharedConversation } from '@/contexts/ConversationContext';
import { useConversationSession } from './useConversationSession';
import type { SessionMessage } from '@/lib/conversation/ConversationSession';
import type { KoiEmotion } from '@/components/avatar/VRMAvatarController';
export interface ChatMessage extends SessionMessage { emotion: KoiEmotion; }
/** Display text for a voice message whose transcript has not arrived (or never will). */
export function voicePlaceholder(status: SessionMessage['status']): string {
  return status === 'pending' ? '🎤 Voice message, transcribing…' : status === 'failed' ? '🎤 Voice message could not be sent' : '🎤 Voice message (interrupted)';
}
export function useChat() {
  const manager = useSharedConversation();
  const recovery = useSyncExternalStore(manager.subscribe, manager.getSnapshot, manager.getSnapshot);
  const session = manager.session!;
  const chat = useConversationSession({ send: async () => { throw new Error('Shared session required'); } }, [], session);
  const messages: ChatMessage[] = chat.messages
    .filter(m => !(m.sender === 'ai' && m.status === 'pending' && !m.content))
    .map(m => ({ ...m, content: m.input === 'voice' && !m.content ? voicePlaceholder(m.status) : m.content, emotion: m.companion_state?.emotion ?? 'neutral' }));
  return { ...chat, messages, sendVoice: (audio: Blob) => session.sendVoice(audio), isTyping: chat.pending, currentEmotion: chat.companion.emotion,
    currentIntensity: chat.companion.intensity, conversationId: session.conversationId,
    blocked: recovery.loading || recovery.completing || !!recovery.error, error: recovery.error ?? chat.error,
    hasUnresolvedHandoff: recovery.hasUnresolvedHandoff, hasQualifyingPair: recovery.hasQualifyingPair };
}
