'use client';
import React from 'react';
import { ChatMessage } from '@/hooks/useChat';

function relativeTime(date: Date): string {
  const diff = Math.floor((Date.now() - date.getTime()) / 1000);
  if (diff < 30) return 'just now';
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
  return date.toLocaleDateString();
}

interface MessageBubbleProps {
  message: ChatMessage;
}

export default function MessageBubble({ message }: MessageBubbleProps) {
  const isUser = message.sender === 'user';

  return (
    <div
      data-sender={message.sender}
      className={`flex flex-col ${isUser ? 'items-end' : 'items-start'} px-4`}
      style={{ animation: 'koiSlideIn 0.28s cubic-bezier(0.34,1.56,0.64,1) both' }}
    >
      <div
        style={{
          maxWidth: '75%',
          padding: '12px 18px',
          borderRadius: isUser ? '18px 18px 4px 18px' : '18px 18px 18px 4px',
          background: isUser ? 'var(--koi-brand)' : 'var(--koi-ai-bubble)',
          color: isUser ? '#fff' : 'var(--koi-dark)',
          border: isUser ? 'none' : '1px solid var(--koi-border)',
          boxShadow: isUser
            ? '0 4px 18px rgba(184,92,56,0.22), 0 1px 4px rgba(184,92,56,0.12)'
            : '0 2px 12px rgba(26,15,7,0.06)',
          fontFamily: isUser ? 'var(--font-body)' : 'var(--font-serif)',
          fontSize: '0.9375rem',
          lineHeight: '1.65',
          letterSpacing: '0.01em',
          wordBreak: 'break-word',
        }}
      >
        {message.content}
      </div>
      <span
        style={{
          fontSize: '0.72rem',
          color: 'var(--koi-muted)',
          marginTop: '4px',
          paddingInline: '4px',
          fontFamily: 'var(--font-body)',
        }}
      >
        {relativeTime(message.timestamp)}
      </span>
    </div>
  );
}
