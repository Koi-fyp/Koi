'use client';
import { useState } from 'react';
import NeoButton from '@/components/ui/NeoButton';

type Language = 'en' | 'ur';

interface Props {
  readonly onNext: (language: Language) => void;
}

const LANGUAGES = [
  { id: 'en' as Language, label: 'English', native: 'English', flag: '🇬🇧' },
  { id: 'ur' as Language, label: 'Urdu',    native: 'اردو',    flag: '🇵🇰' },
];

export default function LanguageStep({ onNext }: Readonly<Props>) {
  const [selected, setSelected] = useState<Language>('en');

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
          Select Language
        </h2>
        <p style={{ fontFamily: 'var(--font-body)', color: '#777', fontSize: '0.9rem', marginBottom: '1.75rem' }}>
          Choose your preferred language.
        </p>

        <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
          {LANGUAGES.map((lang) => {
            const isSelected = selected === lang.id;
            return (
              <button
                key={lang.id}
                onClick={() => setSelected(lang.id)}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                  padding: '1rem 1.25rem',
                  borderRadius: '12px',
                  border: isSelected ? '2.5px solid #000' : '2px solid #ddd',
                  background: isSelected ? 'var(--neo-blue)' : '#fff',
                  boxShadow: isSelected ? '4px 4px 0 0 #000' : 'none',
                  cursor: 'pointer',
                  transition: 'all 0.1s ease',
                  transform: isSelected ? 'translate(-2px, -2px)' : 'none',
                }}
              >
                <div style={{ display: 'flex', alignItems: 'center', gap: '0.875rem' }}>
                  <span style={{ fontSize: '1.5rem' }}>{lang.flag}</span>
                  <span
                    style={{
                      fontFamily: 'var(--font-display)',
                      fontWeight: 700,
                      fontSize: '1rem',
                      color: isSelected ? '#fff' : '#000',
                    }}
                  >
                    {lang.label}
                  </span>
                </div>
                <span
                  style={{
                    fontFamily: 'var(--font-body)',
                    fontSize: '1.1rem',
                    color: isSelected ? 'rgba(255,255,255,0.75)' : '#999',
                  }}
                >
                  {lang.native}
                </span>
              </button>
            );
          })}
        </div>
      </div>

      <NeoButton onClick={() => onNext(selected)} fullWidth style={{ marginTop: '1.5rem' }}>
        Continue →
      </NeoButton>
    </div>
  );
}
