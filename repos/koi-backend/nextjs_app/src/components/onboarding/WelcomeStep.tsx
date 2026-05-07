'use client';
import { useEffect, useCallback } from 'react';

interface Props {
  onNext: () => void;
}

export default function WelcomeStep({ onNext }: Props) {
  const stableOnNext = useCallback(onNext, []);

  useEffect(() => {
    const timer = setTimeout(stableOnNext, 2200);
    return () => clearTimeout(timer);
  }, [stableOnNext]);

  return (
    <div
      onClick={onNext}
      role="button"
      aria-label="Continue"
      style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        flex: 1,
        minHeight: '100svh',
        padding: '3rem 2rem',
        background: '#ffe5d9',
        cursor: 'pointer',
        userSelect: 'none',
        animation: 'fadeUp 0.5s ease both',
      }}
    >
      {/* Square logo with neo border */}
      <div
        style={{
          width: '96px',
          height: '96px',
          borderRadius: '20px',
          background: 'var(--neo-blue)',
          border: '3px solid #000',
          boxShadow: '6px 6px 0 0 #000',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          marginBottom: '2rem',
        }}
      >
        <span
          style={{
            fontFamily: 'var(--font-display)',
            fontWeight: 800,
            fontSize: '2.5rem',
            color: '#fff',
            lineHeight: 1,
          }}
        >
          K
        </span>
      </div>

      <h1
        style={{
          fontFamily: 'var(--font-display)',
          fontWeight: 800,
          fontSize: '3rem',
          letterSpacing: '-0.04em',
          color: '#000',
          marginBottom: '1rem',
          lineHeight: 1,
        }}
      >
        KOI
      </h1>

      <p
        style={{
          fontFamily: 'var(--font-body)',
          fontSize: '1.1rem',
          color: '#666',
          textAlign: 'center',
          maxWidth: '260px',
          lineHeight: 1.6,
          marginBottom: '3rem',
        }}
      >
        Your companion in moments of loneliness
      </p>

      <span
        style={{
          fontFamily: 'var(--font-body)',
          fontSize: '0.78rem',
          color: '#ccc',
          fontWeight: 500,
          letterSpacing: '0.1em',
          textTransform: 'uppercase',
        }}
      >
        Tap to continue
      </span>
    </div>
  );
}
