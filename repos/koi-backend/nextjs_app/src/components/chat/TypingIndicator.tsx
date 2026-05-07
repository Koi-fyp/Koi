'use client';
import React from 'react';

export default function TypingIndicator() {
  return (
    <div
      data-testid="typing-indicator"
      style={{
        display: 'flex',
        alignItems: 'flex-end',
        gap: '10px',
        padding: '2px 16px',
      }}
    >
      {/* Avatar */}
      <div
        style={{
          width: '36px',
          height: '36px',
          borderRadius: '50%',
          background: 'var(--neo-blue)',
          border: '2.5px solid #000',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          fontFamily: 'var(--font-display)',
          fontWeight: 800,
          fontSize: '0.9rem',
          color: '#fff',
          flexShrink: 0,
        }}
      >
        K
      </div>

      {/* Bubble */}
      <div
        style={{
          background: '#fff',
          border: '2.5px solid #000',
          borderRadius: '20px 20px 20px 4px',
          padding: '12px 16px',
          display: 'flex',
          alignItems: 'center',
          gap: '5px',
          boxShadow: '2px 2px 0 0 #000',
        }}
      >
        {[0, 1, 2].map((i) => (
          <span
            key={i}
            style={{
              width: '7px',
              height: '7px',
              borderRadius: '50%',
              background: 'var(--neo-blue)',
              display: 'block',
              animation: `neoDot 1.4s ease-in-out ${i * 0.18}s infinite`,
            }}
          />
        ))}
      </div>
    </div>
  );
}
