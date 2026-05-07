'use client';
import React, { useEffect, useRef } from 'react';
import { ChatMessage } from '@/hooks/useChat';
import MessageBubble from './MessageBubble';
import TypingIndicator from './TypingIndicator';
import HeroText from './HeroText';

interface MessageListProps {
  readonly messages: ChatMessage[];
  readonly isTyping: boolean;
}

export default function MessageList(props: Readonly<MessageListProps>) {
  const { messages, isTyping } = props;
  const bottomRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages, isTyping]);

  return (
    <div
      role="log"
      aria-label="Conversation"
      aria-live="polite"
      style={{
        flex: 1,
        overflowY: 'auto',
        display: 'flex',
        flexDirection: 'column',
        gap: '6px',
        padding: '16px 0 8px',
        scrollbarWidth: 'thin',
        scrollbarColor: '#e5e5e5 transparent',
      }}
    >
      {messages.length === 0 && (
        <div
          style={{
            flex: 1,
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'flex-start',
            justifyContent: 'center',
            padding: '0 1.5rem',
          }}
        >
          <HeroText />
        </div>
      )}

      {messages.map((msg, i) => {
        const showAvatar =
          msg.sender === 'ai' && (i === 0 || messages[i - 1].sender !== 'ai');
        return <MessageBubble key={msg.id} message={msg} showAvatar={showAvatar} />;
      })}

      {isTyping && <TypingIndicator />}

      <div ref={bottomRef} />
    </div>
  );
}
