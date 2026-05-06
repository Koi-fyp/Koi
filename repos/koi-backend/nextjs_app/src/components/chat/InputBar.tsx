'use client';
import React, { useState, useRef, KeyboardEvent } from 'react';

interface InputBarProps {
  onSend: (text: string) => void;
  disabled?: boolean;
}

export default function InputBar({ onSend, disabled = false }: InputBarProps) {
  const [value, setValue] = useState('');
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  const submit = () => {
    const trimmed = value.trim();
    if (!trimmed || disabled) return;
    onSend(trimmed);
    setValue('');
    if (textareaRef.current) textareaRef.current.style.height = 'auto';
  };

  const handleKeyDown = (e: KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      submit();
    }
    if (e.key === 'k' && (e.ctrlKey || e.metaKey)) {
      e.preventDefault();
      setValue('');
      if (textareaRef.current) textareaRef.current.style.height = 'auto';
    }
  };

  const handleInput = () => {
    const el = textareaRef.current;
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = `${Math.min(el.scrollHeight, 128)}px`;
    setValue(el.value);
  };

  return (
    <div
      style={{
        borderTop: '1px solid var(--koi-border)',
        background: 'rgba(250,248,245,0.92)',
        backdropFilter: 'blur(12px)',
        WebkitBackdropFilter: 'blur(12px)',
        padding: '10px 16px',
        display: 'flex',
        alignItems: 'flex-end',
        gap: '10px',
        minHeight: '64px',
      }}
    >
      <textarea
        ref={textareaRef}
        value={value}
        onKeyDown={handleKeyDown}
        onInput={handleInput}
        onChange={(e) => setValue(e.target.value)}
        disabled={disabled}
        placeholder="Talk to Koi…"
        rows={1}
        style={{
          flex: 1,
          resize: 'none',
          border: '1.5px solid var(--koi-border)',
          borderRadius: '14px',
          padding: '10px 14px',
          fontFamily: 'var(--font-body)',
          fontSize: '0.9375rem',
          lineHeight: 1.55,
          color: 'var(--koi-dark)',
          background: 'var(--koi-elevated)',
          outline: 'none',
          overflowY: 'hidden',
          transition: 'border-color 0.18s ease, box-shadow 0.18s ease',
          boxShadow: 'none',
        }}
        onFocus={(e) => {
          e.currentTarget.style.borderColor = 'var(--koi-brand)';
          e.currentTarget.style.boxShadow = '0 0 0 3px rgba(184,92,56,0.12)';
        }}
        onBlur={(e) => {
          e.currentTarget.style.borderColor = 'var(--koi-border)';
          e.currentTarget.style.boxShadow = 'none';
        }}
      />
      <button
        aria-label="Send message"
        onClick={submit}
        disabled={disabled || !value.trim()}
        style={{
          width: '42px',
          height: '42px',
          borderRadius: '12px',
          border: 'none',
          background: disabled || !value.trim() ? 'var(--koi-border)' : 'var(--koi-brand)',
          color: '#fff',
          cursor: disabled || !value.trim() ? 'default' : 'pointer',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          flexShrink: 0,
          transition: 'background 0.18s ease, transform 0.12s ease, box-shadow 0.18s ease',
          boxShadow: disabled || !value.trim()
            ? 'none'
            : '0 4px 14px rgba(184,92,56,0.28)',
        }}
        onMouseDown={(e) => { if (!disabled && value.trim()) e.currentTarget.style.transform = 'scale(0.92)'; }}
        onMouseUp={(e) => { e.currentTarget.style.transform = 'scale(1)'; }}
      >
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none">
          <path d="M22 2L11 13" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"/>
          <path d="M22 2L15 22 11 13 2 9l20-7z" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"/>
        </svg>
      </button>
    </div>
  );
}
