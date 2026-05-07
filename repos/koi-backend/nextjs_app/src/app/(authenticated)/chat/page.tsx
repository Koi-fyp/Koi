'use client';
import React, { useEffect, useRef, useState } from 'react';
import Image from 'next/image';
import { useChat } from '@/hooks/useChat';
import MessageList from '@/components/chat/MessageList';
import InputBar from '@/components/chat/InputBar';

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
        background: 'var(--neo-yellow)',
        color: '#000',
        textAlign: 'center',
        fontSize: '0.8rem',
        fontFamily: 'var(--font-display)',
        fontWeight: 700,
        padding: '7px 16px',
        letterSpacing: '0.03em',
        borderBottom: '2px solid #000',
      }}
    >
      You&rsquo;re offline — your message will send when reconnected
    </div>
  );
}

export default function ChatPage() {
  const { messages, isTyping, send } = useChat();
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const hasMessages = messages.length > 0;

  return (
    <div
      className="flex flex-col-reverse sm:flex-row"
      style={{ height: 'calc(100svh - 66px)', overflow: 'hidden', background: '#ffe5d9' }}
    >
      {/* ── Chat column (left on desktop, bottom on mobile) ── */}
      <div
        className="flex flex-col min-w-0 overflow-hidden"
        style={{ flex: 1 }}
      >
        <OfflineBanner />
        <MessageList messages={messages} isTyping={isTyping} />
        <InputBar onSend={send} disabled={isTyping} inputRef={inputRef} />
      </div>

      {/* ── Avatar panel (right on desktop, top on mobile) ── */}
      <div
        className={`flex flex-col gap-3 ${hasMessages ? 'hidden sm:flex' : 'flex'}`}
        style={{
          width: '100%',
          maxWidth: '340px',
          flexShrink: 0,
          padding: '16px 16px 16px 0',
        }}
      >
        <div className="h-full w-full flex items-center justify-center">
          <div
            className="w-full max-w-[340px] max-h-[80vh] overflow-hidden rounded-[1.5rem] border-[3px] border-black bg-[#FFD100] shadow-[6px_6px_0_0_#000] flex items-center justify-center"
            style={{ maxHeight: '80vh' }}
          >
            <Image
              src="/Male.png"
              alt="KOI companion"
              width={800}
              height={1000}
              priority
              sizes="(min-width: 640px) 340px, 90vw"
              className="h-auto w-full object-contain"
              style={{ objectFit: 'contain' }}
            />
          </div>
        </div>

        {/* CTA — visible only before first message */}
        {!hasMessages && (
          <button
            onClick={() => inputRef.current?.focus()}
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: '8px',
              padding: '14px 20px',
              background: '#fff',
              border: '2.5px solid #000',
              borderRadius: '9999px',
              boxShadow: '4px 4px 0 0 #000',
              fontFamily: 'var(--font-display)',
              fontWeight: 700,
              fontSize: '0.88rem',
              cursor: 'pointer',
              whiteSpace: 'nowrap',
              flexShrink: 0,
              transition: 'transform 0.1s ease, box-shadow 0.1s ease',
            }}
            onMouseDown={(e) => {
              e.currentTarget.style.transform = 'translate(2px,2px)';
              e.currentTarget.style.boxShadow = '2px 2px 0 0 #000';
            }}
            onMouseUp={(e) => {
              e.currentTarget.style.transform = '';
              e.currentTarget.style.boxShadow = '4px 4px 0 0 #000';
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.transform = '';
              e.currentTarget.style.boxShadow = '4px 4px 0 0 #000';
            }}
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
              <path d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
              <polyline points="22,6 12,13 2,6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
            Start a conversation with KOI
          </button>
        )}
      </div>
    </div>
  );
}
