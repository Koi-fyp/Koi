'use client';
import { useState } from 'react';
import NeoButton from '@/components/ui/NeoButton';

type AvatarId = 'female_human' | 'male_human' | 'fox';

interface AvatarOption {
  id: AvatarId;
  label: string;
  emoji: string;
  description: string;
  color: string;
}

const AVATARS: AvatarOption[] = [
  { id: 'female_human', label: 'Aisha', emoji: '👩', description: 'Warm & caring',     color: 'var(--neo-coral)'  },
  { id: 'male_human',   label: 'Raza',  emoji: '👨', description: 'Calm & grounded',   color: 'var(--neo-blue)'   },
  { id: 'fox',          label: 'Koi',   emoji: '🦊', description: 'Playful & curious', color: 'var(--neo-orange)' },
];

interface Props {
  readonly onNext: (avatar: AvatarId) => void;
}

export default function AvatarStep(props: Readonly<Props>) {
  const { onNext } = props;
  const [selected, setSelected] = useState<AvatarId | null>(null);

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
          Choose Your Avatar
        </h2>
        <p style={{ fontFamily: 'var(--font-body)', color: '#777', fontSize: '0.9rem', marginBottom: '1.75rem' }}>
          Pick the look that feels most like you
        </p>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '12px' }}>
          {AVATARS.map((avatar) => {
            const isSelected = selected === avatar.id;
            return (
              <button
                key={avatar.id}
                data-testid={`avatar-${avatar.id}`}
                onClick={() => setSelected(avatar.id)}
                style={{
                  display: 'flex',
                  flexDirection: 'column',
                  alignItems: 'center',
                  padding: '1rem 0.75rem',
                  borderRadius: '12px',
                  border: isSelected ? '2.5px solid #000' : '2px solid #ddd',
                  background: isSelected ? avatar.color : '#fff',
                  boxShadow: isSelected ? '4px 4px 0 0 #000' : 'none',
                  cursor: 'pointer',
                  transition: 'all 0.1s ease',
                  transform: isSelected ? 'translate(-2px, -2px)' : 'none',
                }}
              >
                <span style={{ fontSize: '2.5rem', marginBottom: '0.5rem', lineHeight: 1 }}>
                  {avatar.emoji}
                </span>
                <span
                  style={{
                    fontFamily: 'var(--font-display)',
                    fontWeight: 700,
                    fontSize: '0.875rem',
                    color: isSelected ? '#fff' : '#000',
                  }}
                >
                  {avatar.label}
                </span>
                <span
                  style={{
                    fontFamily: 'var(--font-body)',
                    fontSize: '0.72rem',
                    color: isSelected ? 'rgba(255,255,255,0.8)' : '#888',
                    marginTop: '2px',
                    textAlign: 'center',
                  }}
                >
                  {avatar.description}
                </span>
              </button>
            );
          })}
        </div>
      </div>

      <NeoButton
        onClick={() => selected && onNext(selected)}
        disabled={!selected}
        fullWidth
        style={{ marginTop: '1.5rem' }}
      >
        Continue →
      </NeoButton>
    </div>
  );
}
