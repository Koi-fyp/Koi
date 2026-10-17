'use client';
import React, { useEffect, useRef, useState } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { useChat } from '@/hooks/useChat';
import MessageList from '@/components/chat/MessageList';
import InputBar from '@/components/chat/InputBar';
import { useAuth } from '@/contexts/AuthContext';
import { useAvatarPreference } from '@/hooks/useAvatarPreference';

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
      You&rsquo;re offline — please reconnect before sending a message
    </div>
  );
}

export default function ChatPage() {
  const { messages, isTyping, send, error, blocked } = useChat();
  const { user, loading: authLoading } = useAuth();
  const avatarPreference = useAvatarPreference(user?.uid, authLoading);
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const hasMessages = messages.length > 0;
  const [mounted, setMounted] = useState(false);
  const [avatarImageFailed, setAvatarImageFailed] = useState(false);
  const preference = avatarPreference.status === 'ready' ? avatarPreference.preference : null;
  const imageSrc = preference?.status === 'selected' ? preference.imageSrc : null;
  useEffect(() => setAvatarImageFailed(false), [imageSrc]);

  useEffect(() => {
    setMounted(true);
  }, []);

  return (
    <div
      className="chatLayout"
      style={{ height: 'calc(100svh - 66px)', overflow: 'hidden', background: '#ffe5d9' }}
    >
      {/* ── Chat column (left on desktop, bottom on mobile) ── */}
      <div
        className="chatColumn"
        style={{ flex: 1 }}
      >
        <OfflineBanner />
        <Link href="/companion-scene" style={{ padding: '8px 16px' }}>Open avatar conversation</Link>
        {error && <p role="alert" style={{ padding: '0 16px' }}>{error}</p>}
        <MessageList messages={messages} isTyping={isTyping} />
        <InputBar onSend={send} disabled={isTyping || blocked} inputRef={inputRef} />
      </div>

      {/* ── Avatar panel (right on desktop, top on mobile) ── */}
      <div
        className="avatarPanel"
        data-testid="chat-avatar-panel"
        style={{
          opacity: mounted ? 1 : 0,
          transition: 'opacity 0.4s ease',
        }}
      >
        <div className="avatarStage"
          style={{
            transform: mounted ? 'translateY(0)' : 'translateY(12px)',
            transition: 'transform 0.4s ease',
          }}
        >
          <div className="avatarCard">
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

            {avatarPreference.status === 'loading' ? (
              <p className="avatarFallback" role="status">Loading saved avatar preference…</p>
            ) : avatarPreference.status === 'error' ? (
              <div className="avatarFallback" role="status">
                <p>Your saved companion could not be loaded. The avatar preview is unavailable.</p>
                <Link href="/onboarding">Review companion selection</Link>
              </div>
            ) : preference?.status === 'unselected' ? (
              <div className="avatarFallback" role="status">
                <p>No companion avatar is saved for this account yet.</p>
                <Link href="/onboarding">Choose a companion</Link>
              </div>
            ) : preference?.status === 'selected' && preference.avatar === 'fox' ? (
              <div className="avatarFallback" role="status">
                <p>Your saved Koi fox choice is preserved. A fox preview image is not available.</p>
                <Link href="/companion-scene">Open the 3D avatar conversation</Link>
              </div>
            ) : avatarImageFailed ? (
              <div className="avatarFallback" role="status">
                <p>The companion preview image could not be loaded.</p>
                <Link href="/companion-scene">Open the 3D avatar conversation</Link>
              </div>
            ) : (
              <Image
                key={imageSrc}
                src={imageSrc!}
                alt={`${preference?.displayName || preference?.name || 'KOI'} companion avatar`}
                width={491}
                height={525}
                priority
                sizes="(min-width: 640px) 340px, 215px"
                className="avatarImage"
                onError={() => setAvatarImageFailed(true)}
              />
            )}
          </div>
        </div>

        {/* CTA — visible only before first message */}
        {!hasMessages && (
          <button
            className="avatarCta"
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
        .chatLayout {
          display: flex;
          flex-direction: column-reverse;
        }
        .chatColumn {
          display: flex;
          flex: 1 1 0%;
          flex-direction: column;
          min-width: 0;
          min-height: 0;
          overflow: hidden;
        }
        .avatarPanel {
          box-sizing: border-box;
          display: flex;
          flex: 0 0 clamp(132px, 29svh, 230px);
          flex-direction: column;
          gap: 8px;
          width: 100%;
          min-width: 0;
          padding: 8px 12px;
        }
        .avatarStage {
          display: flex;
          flex: 1 1 0%;
          align-items: center;
          justify-content: center;
          width: 100%;
          min-height: 0;
        }
        .avatarCard {
          position: relative;
          display: flex;
          align-items: center;
          justify-content: center;
          width: auto;
          height: 100%;
          max-width: 100%;
          aspect-ratio: 491 / 525;
          overflow: hidden;
          border: 3px solid #000;
          border-radius: 1.25rem;
          background: #ffc224;
          box-shadow: 5px 5px 0 #000;
        }
        .avatarImage {
          position: relative;
          z-index: 1;
          display: block;
          width: 100%;
          height: 100%;
          object-fit: contain;
        }
        .avatarFallback {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 8px;
          max-width: 28rem;
          padding: 16px;
          text-align: center;
          font-size: 0.85rem;
          font-weight: 600;
        }
        .avatarFallback a { color: #000; text-decoration: underline; }
        .avatarCta { display: none !important; }
        @media (min-width: 640px) {
          .chatLayout { flex-direction: row; }
          .avatarPanel {
            flex: 0 0 min(340px, 38vw);
            width: min(340px, 38vw);
            max-width: 38vw;
            padding: 16px 16px 16px 0;
          }
          .avatarCard { width: 100%; height: auto; max-height: 80vh; }
          .avatarCta { display: flex !important; }
        }
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
