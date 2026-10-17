'use client';
import { useState } from 'react';
import NeoButton from '@/components/ui/NeoButton';
import NeoCard from '@/components/ui/NeoCard';

interface Props {
  onComplete: (notificationTime: string, notificationsEnabled: boolean) => void;
  saving?: boolean;
  disabled?: boolean;
  initialEnabled?: boolean;
  initialTime?: string;
}

export default function NotificationStep({ onComplete, saving = false, disabled = false, initialEnabled = true, initialTime = '20:00' }: Props) {
  const [enabled, setEnabled] = useState(initialEnabled);
  const [time, setTime]       = useState(initialTime);

  return (
    <div
      style={{
        display: 'flex',
        flexDirection: 'column',
        flex: 1,
        padding: '1.5rem',
        maxWidth: '480px',
        margin: '0 auto',
        width: '100%',
      }}
    >
      <div style={{ flex: 1 }}>
        <h2
          style={{
            fontFamily: 'var(--font-display)',
            fontWeight: 800,
            fontSize: '2rem',
            letterSpacing: '-0.03em',
            color: '#000',
            marginBottom: '0.375rem',
          }}
        >
          Daily Check-ins
        </h2>
        <p style={{ fontFamily: 'var(--font-body)', color: '#777', fontSize: '0.9rem', marginBottom: '1.75rem' }}>
          Save a preferred check-in time on this device. Web notifications and scheduled messages are not enabled.
        </p>

        {/* Toggle */}
        <NeoCard className="p-4 mb-3">
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
            <div>
              <p style={{ fontFamily: 'var(--font-display)', fontWeight: 700, fontSize: '0.9rem', color: '#000' }}>
                Save daily check-in preference
              </p>
              <p style={{ fontFamily: 'var(--font-body)', fontSize: '0.78rem', color: '#999', marginTop: '2px' }}>
                Preference only; no notification is scheduled
              </p>
            </div>
            <button
              role="switch"
              aria-checked={enabled}
              onClick={() => setEnabled((v) => !v)}
              style={{
                position: 'relative',
                width: '52px',
                height: '28px',
                borderRadius: '14px',
                border: '2px solid #000',
                background: enabled ? 'var(--neo-blue)' : '#ddd',
                cursor: 'pointer',
                transition: 'background 0.2s ease',
                flexShrink: 0,
                padding: 0,
              }}
            >
              <span
                style={{
                  position: 'absolute',
                  top: '2px',
                  left: enabled ? '24px' : '2px',
                  width: '20px',
                  height: '20px',
                  borderRadius: '10px',
                  background: '#fff',
                  border: '1.5px solid #000',
                  transition: 'left 0.2s ease',
                }}
              />
            </button>
          </div>
        </NeoCard>

        {enabled && (
          <NeoCard className="p-4">
            <label
              htmlFor="notif-time"
              style={{
                display: 'block',
                fontFamily: 'var(--font-display)',
                fontWeight: 700,
                fontSize: '0.875rem',
                color: '#000',
                marginBottom: '0.625rem',
              }}
            >
              Reminder time
            </label>
            <input
              id="notif-time"
              type="time"
              value={time}
              min="06:00"
              max="23:00"
              onChange={(e) => setTime(e.target.value)}
              className="neo-input"
              style={{
                fontFamily: 'var(--font-display)',
                fontWeight: 700,
                fontSize: '1.5rem',
                textAlign: 'center',
                letterSpacing: '0.04em',
              }}
            />
            <p style={{ fontFamily: 'var(--font-body)', fontSize: '0.72rem', color: '#aaa', marginTop: '0.5rem' }}>
              Available 6:00 AM – 11:00 PM
            </p>
          </NeoCard>
        )}
      </div>

      <NeoButton
        variant="secondary"
        disabled={saving || disabled}
        onClick={() => onComplete(time, enabled)}
        fullWidth
        style={{ marginTop: '1.5rem' }}
      >
        {saving ? 'Saving companion...' : <>Let&apos;s Go ✦</>}
      </NeoButton>
    </div>
  );
}
