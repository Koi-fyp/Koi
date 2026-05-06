'use client';
import React from 'react';

export default function TypingIndicator() {
  return (
    <div
      data-testid="typing-indicator"
      className="flex items-center gap-1 px-4 py-3 self-start"
      style={{ maxWidth: '75%' }}
    >
      <div
        style={{
          background: 'var(--koi-ai-bubble)',
          border: '1px solid var(--koi-border)',
          borderRadius: '18px 18px 18px 4px',
          padding: '12px 18px',
          display: 'flex',
          alignItems: 'center',
          gap: '6px',
          boxShadow: '0 2px 12px rgba(184,92,56,0.06)',
        }}
      >
        {[0, 1, 2].map((i) => (
          <span
            key={i}
            style={{
              width: '7px',
              height: '7px',
              borderRadius: '50%',
              background: 'var(--koi-muted)',
              display: 'block',
              animation: `koiDot 1.4s ease-in-out ${i * 0.18}s infinite`,
            }}
          />
        ))}
      </div>
    </div>
  );
}
