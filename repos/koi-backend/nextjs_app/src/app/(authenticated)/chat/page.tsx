'use client';
import React, { useEffect, useState } from 'react';
import { useChat } from '@/hooks/useChat';
import MessageList from '@/components/chat/MessageList';
import InputBar from '@/components/chat/InputBar';
import AvatarRenderer from '@/components/avatar/AvatarRenderer';
import type { Emotion } from '@/lib/conversation/conversationService';

const EMOTION_TINTS: Record<Emotion, string> = {
  happy:   'radial-gradient(ellipse at 50% 100%, #FFF9C4 0%, #FAF8F5 70%)',
  sad:     'radial-gradient(ellipse at 50% 100%, #E3F2FD 0%, #FAF8F5 70%)',
  anxious: 'radial-gradient(ellipse at 50% 100%, #FFF3E0 0%, #FAF8F5 70%)',
  calm:    'radial-gradient(ellipse at 50% 100%, #E8F5E9 0%, #FAF8F5 70%)',
  neutral: 'radial-gradient(ellipse at 50% 100%, #F5F0EB 0%, #FAF8F5 70%)',
};

function OfflineBanner() {
  const [offline, setOffline] = useState(false);
  useEffect(() => {
    const on  = () => setOffline(false);
    const off = () => setOffline(true);
    if (typeof navigator !== 'undefined' && !navigator.onLine) setOffline(true);
    globalThis.addEventListener('online', on);
    globalThis.addEventListener('offline', off);
    return () => {
      globalThis.removeEventListener('online', on);
      globalThis.removeEventListener('offline', off);
    };
  }, []);

  if (!offline) return null;
  return (
    <div
      role="alert"
      style={{
        background: 'var(--koi-brand, #B85C38)',
        color: '#fff',
        textAlign: 'center',
        fontSize: '0.8rem',
        padding: '6px 16px',
        letterSpacing: '0.02em',
      }}
    >
      You&rsquo;re offline — your message will send when reconnected
    </div>
  );
}

export default function ChatPage() {
  const { messages, isTyping, currentEmotion, send } = useChat();

  return (
    <div
      style={{
        display: 'flex',
        flexDirection: 'column',
        height: 'calc(100vh - 4rem)',
        background: '#FAF8F5',
        overflow: 'hidden',
      }}
    >
      {/* Avatar panel */}
      <div
        role="img"
        aria-label="KOI avatar"
        style={{
          height: '200px',
          flexShrink: 0,
          background: EMOTION_TINTS[currentEmotion],
          transition: 'background 0.6s ease',
          position: 'relative',
          overflow: 'hidden',
        }}
      >
        <svg
          aria-hidden="true"
          style={{
            position: 'absolute', inset: 0, width: '100%', height: '100%',
            opacity: 0.04, pointerEvents: 'none',
          }}
        >
          <filter id="koi-grain">
            <feTurbulence type="fractalNoise" baseFrequency="0.72" numOctaves="4" stitchTiles="stitch" />
            <feColorMatrix type="saturate" values="0" />
          </filter>
          <rect width="100%" height="100%" filter="url(#koi-grain)" />
        </svg>

        <AvatarRenderer emotion={currentEmotion} />

        <div
          style={{
            position: 'absolute',
            bottom: '12px',
            left: '50%',
            transform: 'translateX(-50%)',
            fontFamily: 'Georgia, serif',
            fontStyle: 'italic',
            fontSize: '0.78rem',
            color: '#9E8C82',
            letterSpacing: '0.12em',
            pointerEvents: 'none',
          }}
        >
          koi
        </div>
      </div>

      <OfflineBanner />

      {/* Message list */}
      <MessageList messages={messages} isTyping={isTyping} />

      {/* Input bar */}
      <InputBar onSend={send} disabled={isTyping} />
    </div>
  );
}
