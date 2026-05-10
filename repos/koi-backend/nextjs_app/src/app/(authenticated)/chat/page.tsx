'use client';
import React, { useEffect, useRef, useState } from 'react';
import Image from 'next/image';
import Link from 'next/link';
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
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

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
        <div
          className="h-full w-full flex items-center justify-center"
          style={{
            opacity: mounted ? 1 : 0,
            transform: mounted ? 'translateY(0)' : 'translateY(20px)',
            transition: 'opacity 0.8s cubic-bezier(0.34, 1.56, 0.64, 1), transform 0.8s cubic-bezier(0.34, 1.56, 0.64, 1)',
          }}
        >
          <div
            className="w-full max-w-[340px] max-h-[80vh] overflow-hidden rounded-[1.5rem] border-[3px] border-black bg-[#FFD100] shadow-[6px_6px_0_0_#000] flex items-center justify-center relative"
            style={{ maxHeight: '80vh' }}
          >
            {/* Thinking bubbles - show when typing */}
            {isTyping && (
              <>
                <div
                  style={{
                    position: 'absolute',
                    bottom: '35%',
                    right: '15%',
                    width: '60px',
                    height: '60px',
                    borderRadius: '50%',
                    background: 'rgba(0, 0, 0, 0.15)',
                    animation: 'thinkBubble1 2s ease-in-out infinite',
                    zIndex: 1,
                  }}
                />
                <div
                  style={{
                    position: 'absolute',
                    bottom: '45%',
                    right: '10%',
                    width: '40px',
                    height: '40px',
                    borderRadius: '50%',
                    background: 'rgba(0, 0, 0, 0.12)',
                    animation: 'thinkBubble2 2s ease-in-out 0.3s infinite',
                    zIndex: 1,
                  }}
                />
                <div
                  style={{
                    position: 'absolute',
                    bottom: '52%',
                    right: '8%',
                    width: '24px',
                    height: '24px',
                    borderRadius: '50%',
                    background: 'rgba(0, 0, 0, 0.1)',
                    animation: 'thinkBubble3 2s ease-in-out 0.6s infinite',
                    zIndex: 1,
                  }}
                />
              </>
            )}

            <Image
              src="/Male.png"
              alt="KOI companion"
              width={800}
              height={1000}
              priority
              sizes="(min-width: 640px) 340px, 90vw"
              className="h-auto w-full object-contain relative z-10"
              style={{
                objectFit: 'contain',
              }}
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
              opacity: mounted ? 1 : 0,
              transform: mounted ? 'translateY(0)' : 'translateY(10px)',
              transitionDelay: '0.3s',
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
            Try other avatars too!
          </button>
        )}
      </div>

      <style jsx>{`
        @keyframes thinkBubble1 {
          0%, 100% {
            transform: scale(0.8) translateY(0);
            opacity: 0;
          }
          50% {
            transform: scale(1) translateY(-10px);
            opacity: 0.6;
          }
        }

        @keyframes thinkBubble2 {
          0%, 100% {
            transform: scale(0.8) translateY(0);
            opacity: 0;
          }
          50% {
            transform: scale(1) translateY(-8px);
            opacity: 0.5;
          }
        }

        @keyframes thinkBubble3 {
          0%, 100% {
            transform: scale(0.8) translateY(0);
            opacity: 0;
          }
          50% {
            transform: scale(1) translateY(-6px);
            opacity: 0.4;
          }
        }
      `}</style>
    </div>
  );
}
