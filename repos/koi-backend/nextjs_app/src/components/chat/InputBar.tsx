'use client';
import React, { useState, useRef, KeyboardEvent } from 'react';

interface InputBarProps {
  onSend: (text: string) => void;
  disabled?: boolean;
  inputRef?: React.RefObject<HTMLTextAreaElement>;
}

export default function InputBar({ onSend, disabled = false, inputRef }: InputBarProps) {
  const [value, setValue] = useState('');
  const internalRef = useRef<HTMLTextAreaElement>(null);
  const textareaRef = inputRef ?? internalRef;

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

  const canSend = !disabled && value.trim().length > 0;

  return (
    <div style={{ padding: '10px 16px 14px', background: '#ffe5d9', flexShrink: 0 }}>
      <div
        style={{
          display: 'flex',
          alignItems: 'flex-end',
          gap: '10px',
          background: '#fff',
          border: '2.5px solid #000',
          borderRadius: '28px',
          padding: '8px 8px 8px 18px',
          boxShadow: '3px 3px 0 0 #000',
        }}
      >
        <textarea
          ref={textareaRef}
          value={value}
          onKeyDown={handleKeyDown}
          onInput={handleInput}
          onChange={(e) => setValue(e.target.value)}
          disabled={disabled}
          placeholder="Type your message..."
          rows={1}
          style={{
            flex: 1,
            resize: 'none',
            overflowY: 'hidden',
            minHeight: '36px',
            maxHeight: '128px',
            lineHeight: 1.55,
            border: 'none',
            outline: 'none',
            background: 'transparent',
            fontFamily: 'var(--font-body)',
            fontSize: '0.9375rem',
            color: '#000',
            padding: '4px 0',
          }}
        />
        <button
          aria-label="Send message"
          onClick={submit}
          disabled={!canSend}
          style={{
            width: '40px',
            height: '40px',
            borderRadius: '50%',
            border: '2px solid #000',
            background: canSend ? '#000' : '#e0e0e0',
            color: canSend ? '#fff' : '#aaa',
            cursor: canSend ? 'pointer' : 'default',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            flexShrink: 0,
            transition: 'background 0.12s ease, transform 0.1s ease',
          }}
          onMouseDown={(e) => { if (canSend) e.currentTarget.style.transform = 'scale(0.92)'; }}
          onMouseUp={(e) => { e.currentTarget.style.transform = ''; }}
          onMouseLeave={(e) => { e.currentTarget.style.transform = ''; }}
        >
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none">
            <path d="M22 2L11 13" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
            <path d="M22 2L15 22 11 13 2 9l20-7z" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </button>
      </div>
    </div>
  );
}
