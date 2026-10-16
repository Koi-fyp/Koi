'use client';
import { useState } from 'react';
export default function ChatComposer({ onSend, onCancel, pending, error, onFocusChange, development = false, disabled = false }: {
  onSend: (text: string) => Promise<void>; onCancel: () => void; pending: boolean; error: string | null;
  disabled?: boolean;
  onFocusChange?: (focused: boolean) => void; development?: boolean;
}) {
  const [text, setText] = useState('');
  return <div style={{ width: 'min(100%, 760px)', margin: '0 auto 10px', fontSize: 12 }}>
    {error && <p role="alert" style={{ margin: '0 0 6px', color: '#a42c38' }}>{error}</p>}
    <form onSubmit={(event) => { event.preventDefault(); if (!text.trim() || pending || disabled) return; void onSend(text); setText(''); }} style={{ display: 'flex', gap: 8 }}>
      <input aria-label={development ? 'Development mock message' : 'Message KOI'} value={text} onChange={(event) => { setText(event.target.value); onFocusChange?.(true); }} onFocus={() => onFocusChange?.(true)} onBlur={() => onFocusChange?.(false)}
        placeholder={development ? 'Use the scripted sample buttons' : 'Type your message'} readOnly={development} disabled={disabled} style={{ minWidth: 0, flex: 1, padding: 10, borderRadius: 12, border: '1px solid #c9b6a5', font: 'inherit' }} />
      <button type="submit" disabled={pending || disabled || !text.trim() || development} style={{ padding: '8px 14px', borderRadius: 12, border: '1px solid #c9b6a5', background: '#ffd100' }}>Send</button>
      {pending && <button type="button" onClick={onCancel} style={{ border: '1px solid #c9b6a5', borderRadius: 12, padding: 8 }}>Cancel request</button>}
    </form>
    <p role="status" style={{ margin: '5px 0 0', color: '#75685e' }}>{pending ? 'Connecting to KOI. The self-hosted service can take a little while to respond; you can cancel anytime.' : 'Text conversation only. No audio is playing.'}</p>
  </div>;
}
