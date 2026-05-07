import NeoButton from '@/components/ui/NeoButton';
import NeoCard from '@/components/ui/NeoCard';

interface Props {
  onNext: () => void;
}

const STORED = [
  'Anonymous session ID (no name required)',
  'Your conversations (encrypted, on your device)',
  'Check-in mood responses',
  'Your avatar and language preference',
];

const NOT_STORED = [
  'Your real name or contact details',
  'Location data',
  'Conversations shared with third parties',
  'Any data sold to advertisers',
];

export default function PrivacyStep({ onNext }: Props) {
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
      <div style={{ flex: 1, overflowY: 'auto', paddingBottom: '1rem' }}>
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
          Privacy Matters
        </h2>
        <p
          style={{
            fontFamily: 'var(--font-body)',
            color: '#777',
            fontSize: '0.9rem',
            marginBottom: '1.5rem',
          }}
        >
          Here&apos;s what you should know about your data.
        </p>

        <NeoCard className="p-4 mb-4">
          <h3
            style={{
              fontFamily: 'var(--font-display)',
              fontWeight: 700,
              fontSize: '0.875rem',
              marginBottom: '0.875rem',
              display: 'flex',
              alignItems: 'center',
              gap: '0.5rem',
              color: '#000',
            }}
          >
            <span
              style={{
                width: '20px',
                height: '20px',
                background: 'var(--neo-mint)',
                border: '2px solid #000',
                borderRadius: '4px',
                flexShrink: 0,
                display: 'inline-block',
              }}
            />
            What we store
          </h3>
          <ul style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', listStyle: 'none', padding: 0, margin: 0 }}>
            {STORED.map((item) => (
              <li
                key={item}
                style={{
                  fontFamily: 'var(--font-body)',
                  fontSize: '0.875rem',
                  color: '#444',
                  display: 'flex',
                  gap: '0.625rem',
                  alignItems: 'flex-start',
                }}
              >
                <span style={{ color: 'var(--neo-mint)', fontWeight: 700, flexShrink: 0, marginTop: '1px' }}>✓</span>
                {item}
              </li>
            ))}
          </ul>
        </NeoCard>

        <NeoCard className="p-4">
          <h3
            style={{
              fontFamily: 'var(--font-display)',
              fontWeight: 700,
              fontSize: '0.875rem',
              marginBottom: '0.875rem',
              display: 'flex',
              alignItems: 'center',
              gap: '0.5rem',
              color: '#000',
            }}
          >
            <span
              style={{
                width: '20px',
                height: '20px',
                background: 'var(--neo-coral)',
                border: '2px solid #000',
                borderRadius: '4px',
                flexShrink: 0,
                display: 'inline-block',
              }}
            />
            What we never store
          </h3>
          <ul style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', listStyle: 'none', padding: 0, margin: 0 }}>
            {NOT_STORED.map((item) => (
              <li
                key={item}
                style={{
                  fontFamily: 'var(--font-body)',
                  fontSize: '0.875rem',
                  color: '#444',
                  display: 'flex',
                  gap: '0.625rem',
                  alignItems: 'flex-start',
                }}
              >
                <span style={{ color: 'var(--neo-coral)', fontWeight: 700, flexShrink: 0, marginTop: '1px' }}>✗</span>
                {item}
              </li>
            ))}
          </ul>
        </NeoCard>
      </div>

      <NeoButton onClick={onNext} fullWidth style={{ marginTop: '1rem' }}>
        I Understand →
      </NeoButton>
    </div>
  );
}
