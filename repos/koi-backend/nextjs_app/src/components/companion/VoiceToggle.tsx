'use client';
import { useId } from 'react';
import type { VoiceLine } from '@/lib/speech/useSpokenReplies';
const LINES: Record<VoiceLine, string> = { idle: '', speaking: 'Speaking...', skipped: 'Voice skipped for this reply', unavailable: 'Voice unavailable right now' };
/** "Spoken replies" switch. Off by default; the parent persists it per uid (useVoiceEnabled). */
export default function VoiceToggle({ checked, onChange, configured, companionHasVoice, signedIn = true, line = 'idle' }: {
  checked: boolean; onChange: (enabled: boolean) => void; configured: boolean; companionHasVoice: boolean; signedIn?: boolean; line?: VoiceLine;
}) {
  const id = useId();
  const reason = !configured ? 'Voice is not configured' : !companionHasVoice ? 'No voice for this companion' : null;
  const disabled = !!reason || !signedIn;
  const on = checked && !disabled;
  return <div style={{ width: 'min(100%, 760px)', margin: '6px auto 0', fontSize: 12, color: '#4c4038' }}>
    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
      <button type="button" role="switch" id={`${id}-switch`} aria-checked={on} aria-describedby={`${id}-note`} disabled={disabled} onClick={() => onChange(!on)}
        style={{ minHeight: 32, minWidth: 52, borderRadius: 16, border: '1px solid #c9b6a5', background: on ? '#ffd100' : '#f3ece6', font: 'inherit' }}>{on ? 'On' : 'Off'}</button>
      <label htmlFor={`${id}-switch`}>Spoken replies</label>
      {reason && <span>{reason}</span>}
    </div>
    <p id={`${id}-note`} style={{ margin: '4px 0 0', color: '#75685e' }}>Spoken replies are sent to KOI&apos;s speech service. Replies in Roman Urdu or mixed script stay text-only.</p>
    <p role="status" aria-live="polite" style={{ margin: '2px 0 0', minHeight: '1.2em' }}>{on ? LINES[line] : ''}</p>
  </div>;
}
