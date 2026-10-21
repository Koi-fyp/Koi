'use client';
import { useState } from 'react';
import NeoButton from '@/components/ui/NeoButton';
import NeoCard from '@/components/ui/NeoCard';

interface Props {
  onNext: () => void;
}

interface CheckItem {
  id: string;
  label: string;
  checked: boolean;
  onChange: () => void;
}

export default function AIDisclosureStep({ onNext }: Props) {
  const [checkedAI, setCheckedAI]           = useState(false);
  const [checkedPrivacy, setCheckedPrivacy] = useState(false);

  const checks: CheckItem[] = [
    {
      id: 'ai',
      label: 'I understand KOI is an AI, not a therapist',
      checked: checkedAI,
      onChange: () => setCheckedAI((v) => !v),
    },
    {
      id: 'privacy',
      label: 'I understand saved history is encrypted, while inference receives readable text',
      checked: checkedPrivacy,
      onChange: () => setCheckedPrivacy((v) => !v),
    },
  ];

  return (
    <div className="flex flex-col flex-1 lg:flex-none w-full max-w-5xl mx-auto p-6 lg:px-8 lg:py-10">
      <div className="flex-1 lg:flex-none pb-4">
        <h2
          style={{
            fontFamily: 'var(--font-display)',
            fontWeight: 800,
            fontSize: '2rem',
            letterSpacing: '-0.03em',
            color: '#000',
            marginBottom: '1.25rem',
          }}
        >
          Important Notice
        </h2>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-x-6 lg:gap-x-8 items-start [&>*]:min-w-0">
        {/* Warning card */}
        <NeoCard variant="yellow" className="p-4 mb-4">
          <div style={{ display: 'flex', gap: '0.75rem', alignItems: 'flex-start' }}>
            <span style={{ fontSize: '1.25rem', flexShrink: 0 }}>⚠</span>
            <div>
              <p
                style={{
                  fontFamily: 'var(--font-display)',
                  fontWeight: 700,
                  fontSize: '0.9rem',
                  color: '#000',
                  marginBottom: '0.375rem',
                }}
              >
                KOI is an AI, not a therapist
              </p>
              <p style={{ fontFamily: 'var(--font-body)', fontSize: '0.85rem', color: '#333', lineHeight: 1.55 }}>
                KOI cannot diagnose mental health conditions and is not a substitute for professional care.
                In an emergency, contact emergency services immediately.
              </p>
            </div>
          </div>
        </NeoCard>

        {/* Crisis helplines */}
        <NeoCard className="p-4 mb-5">
          <h3
            style={{
              fontFamily: 'var(--font-display)',
              fontWeight: 700,
              fontSize: '0.85rem',
              color: '#000',
              marginBottom: '0.875rem',
              display: 'flex',
              alignItems: 'center',
              gap: '0.5rem',
            }}
          >
            <span
              style={{
                background: 'var(--neo-coral)',
                color: '#fff',
                width: '20px',
                height: '20px',
                display: 'inline-flex',
                alignItems: 'center',
                justifyContent: 'center',
                borderRadius: '4px',
                border: '2px solid #000',
                fontSize: '0.7rem',
                fontWeight: 800,
                flexShrink: 0,
              }}
            >
              !
            </span>
            Crisis Helplines (Pakistan)
          </h3>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '0.625rem' }}>
            {[
              { name: 'Umang (Mental Health)', tel: '0311-7786264', href: 'tel:03117786264' },
              { name: 'Rozan Counselling',     tel: '0800-22444',   href: 'tel:080022444'  },
              { name: 'Emergency Services',    tel: '15 / 1122',    href: 'tel:15'         },
            ].map(({ name, tel, href }) => (
              <div key={name} style={{ display: 'flex', flexWrap: 'wrap', gap: '0.5rem', justifyContent: 'space-between', alignItems: 'center' }}>
                <span style={{ fontFamily: 'var(--font-body)', fontSize: '0.85rem', color: '#444' }}>{name}</span>
                <a
                  href={href}
                  style={{
                    fontFamily: 'var(--font-display)',
                    fontWeight: 700,
                    fontSize: '0.85rem',
                    color: 'var(--neo-coral)',
                    textDecoration: 'none',
                  }}
                >
                  {tel}
                </a>
              </div>
            ))}
          </div>
        </NeoCard>

        </div>

        <section className="max-w-3xl" aria-label="Required acknowledgments">
        {/* Checkboxes */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '0.875rem' }}>
          {checks.map(({ id, label, checked, onChange }) => (
            <label
              key={id}
              style={{ display: 'flex', alignItems: 'flex-start', gap: '0.75rem', cursor: 'pointer' }}
            >
              <button
                type="button"
                role="checkbox"
                aria-checked={checked}
                onClick={onChange}
                style={{
                  width: '22px',
                  height: '22px',
                  borderRadius: '4px',
                  border: '2.5px solid #000',
                  background: checked ? 'var(--neo-blue)' : '#fff',
                  boxShadow: '2px 2px 0 0 #000',
                  flexShrink: 0,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  cursor: 'pointer',
                  transition: 'background 0.15s ease',
                  marginTop: '1px',
                  padding: 0,
                }}
              >
                {checked && (
                  <svg width="13" height="13" viewBox="0 0 12 12" fill="none">
                    <path d="M2 6l3 3 5-5" stroke="white" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                )}
              </button>
              <span style={{ fontFamily: 'var(--font-body)', fontSize: '0.9rem', color: '#333', lineHeight: 1.5 }}>
                {label}
              </span>
            </label>
          ))}
        </div>
      <NeoButton
        className="lg:max-w-md"
        onClick={onNext}
        disabled={!checkedAI || !checkedPrivacy}
        fullWidth
        style={{ marginTop: '1rem' }}
      >
        I Agree →
      </NeoButton>
        </section>
      </div>
    </div>
  );
}
