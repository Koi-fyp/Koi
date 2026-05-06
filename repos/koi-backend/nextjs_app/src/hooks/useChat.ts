'use client';
import { useState, useEffect, useCallback, useRef } from 'react';
import { v4 as uuidv4 } from 'uuid';
import { db, MessageRecord } from '@/lib/db';
import { auth } from '@/lib/firebase';
import {
  sendMessage as callService,
  Emotion,
} from '@/lib/conversation/conversationService';

export interface ChatMessage {
  id: string;
  conversationId: string;
  sender: 'user' | 'ai';
  content: string;
  timestamp: Date;
  emotion: Emotion;
}

interface UseChatReturn {
  messages: ChatMessage[];
  isTyping: boolean;
  currentEmotion: Emotion;
  conversationId: string;
  send: (text: string) => Promise<void>;
}

function toChat(r: MessageRecord): ChatMessage {
  return {
    id: r.id,
    conversationId: r.conversationId,
    sender: r.sender,
    content: r.content,
    timestamp: r.timestamp,
    emotion: (r.emotion as Emotion) ?? 'neutral',
  };
}

export function useChat(): UseChatReturn {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [isTyping, setIsTyping] = useState(false);
  const [currentEmotion, setCurrentEmotion] = useState<Emotion>('neutral');
  const conversationId = useRef(uuidv4());
  const offlineQueue = useRef<Array<() => Promise<void>>>([]);

  // Read uid at call time — auth.currentUser is populated after signInWithCustomToken
  const getUserId = () => auth.currentUser?.uid ?? 'anonymous';

  useEffect(() => {
    db.messages
      .where('conversationId')
      .equals(conversationId.current)
      .sortBy('timestamp')
      .then((rows) => setMessages(rows.map(toChat)))
      .catch(() => {});
  }, []);

  useEffect(() => {
    const flush = async () => {
      const tasks = offlineQueue.current.splice(0);
      for (const task of tasks) {
        try { await task(); } catch { /* keep going */ }
      }
    };
    window.addEventListener('online', flush);
    return () => window.removeEventListener('online', flush);
  }, []);

  const send = useCallback(async (text: string) => {
    const trimmed = text.trim();
    if (!trimmed) return;

    const optimistic: ChatMessage = {
      id: uuidv4(),
      conversationId: conversationId.current,
      sender: 'user',
      content: trimmed,
      timestamp: new Date(),
      emotion: 'neutral',
    };

    setMessages((prev) => [...prev, optimistic]);
    setIsTyping(true);

    const doSend = async () => {
      try {
        // Build last-5 context for the AI
        const context = messages.slice(-5).map((m) => ({
          role: (m.sender === 'user' ? 'user' : 'model') as 'user' | 'model',
          content: m.content,
        }));
        const result = await callService(
          getUserId(),
          conversationId.current,
          trimmed,
          context,
          { severity: 'mild', profile: 'disconnected', avatar: 'fox' },
        );

        setCurrentEmotion(result.emotion);
        setMessages((prev) => [
          ...prev,
          {
            id: uuidv4(),
            conversationId: conversationId.current,
            sender: 'ai',
            content: result.reply,
            timestamp: new Date(),
            emotion: result.emotion,
          },
        ]);
      } finally {
        setIsTyping(false);
      }
    };

    if (typeof navigator !== 'undefined' && !navigator.onLine) {
      offlineQueue.current.push(doSend);
      setIsTyping(false);
    } else {
      await doSend();
    }
  }, []);

  return {
    messages,
    isTyping,
    currentEmotion,
    conversationId: conversationId.current,
    send,
  };
}
