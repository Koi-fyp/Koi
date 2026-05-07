'use client';

interface RowProps {
  icon: string;
  label: string;
  desc: string;
  danger?: boolean;
  toggle?: boolean;
  on?: boolean;
}

function SettingsRow({ icon, label, desc, danger = false, toggle = false, on = false }: RowProps) {
  return (
    <button
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: '0.875rem',
        width: '100%',
        padding: '0.875rem 0',
        background: 'none',
        border: 'none',
        cursor: 'pointer',
        textAlign: 'left',
      }}
    >
      <span
        style={{
          width: '38px',
          height: '38px',
          borderRadius: '8px',
          background: 'var(--neo-gray)',
          border: '2px solid #000',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          fontSize: '1.1rem',
          flexShrink: 0,
        }}
      >
        {icon}
      </span>
      <div style={{ flex: 1, minWidth: 0 }}>
        <p style={{ fontFamily: 'var(--font-display)', fontWeight: 700, fontSize: '0.9rem', color: danger ? '#FF4136' : '#000' }}>
          {label}
        </p>
        <p style={{ fontFamily: 'var(--font-body)', fontSize: '0.78rem', color: '#999', marginTop: '1px' }}>
          {desc}
        </p>
      </div>
      {toggle ? (
        <div
          style={{
            width: '44px',
            height: '24px',
            borderRadius: '12px',
            background: on ? 'var(--neo-blue)' : '#ddd',
            border: '2px solid #000',
            position: 'relative',
            flexShrink: 0,
          }}
        >
          <span
            style={{
              position: 'absolute',
              top: '2px',
              left: on ? '20px' : '2px',
              width: '16px',
              height: '16px',
              borderRadius: '8px',
              background: '#fff',
              border: '1.5px solid #000',
            }}
          />
        </div>
      ) : (
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none">
          <path d="M9 18l6-6-6-6" stroke="#ccc" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      )}
    </button>
  );
}

const DIVIDER = <div style={{ height: '1px', background: '#f0f0f0' }} />;

export default function SettingsPage() {
  return (
    <div style={{ padding: '1.5rem 1.5rem 0', maxWidth: '480px', margin: '0 auto' }}>
      <h1
        style={{
          fontFamily: 'var(--font-display)',
          fontWeight: 800,
          fontSize: '2rem',
          letterSpacing: '-0.03em',
          color: '#000',
          marginBottom: '1.5rem',
        }}
      >
        Settings
      </h1>

      {/* Account */}
      <p style={{ fontFamily: 'var(--font-display)', fontWeight: 800, fontSize: '0.7rem', color: '#bbb', letterSpacing: '0.1em', textTransform: 'uppercase', marginBottom: '0.5rem', paddingLeft: '2px' }}>Account</p>
      <div style={{ background: '#fff', border: '2.5px solid #000', borderRadius: '1.25rem', boxShadow: '4px 4px 0 0 #000', padding: '0 1rem', marginBottom: '1.25rem' }}>
        <SettingsRow icon="👤" label="Avatar & Name"  desc="Change your companion" />
        {DIVIDER}
        <SettingsRow icon="🌐" label="Language"        desc="English" />
        {DIVIDER}
        <SettingsRow icon="🗑" label="Clear History"   desc="Delete all conversations" danger />
      </div>

      {/* Notifications — yellow card */}
      <p style={{ fontFamily: 'var(--font-display)', fontWeight: 800, fontSize: '0.7rem', color: '#bbb', letterSpacing: '0.1em', textTransform: 'uppercase', marginBottom: '0.5rem', paddingLeft: '2px' }}>Notifications</p>
      <div style={{ background: 'var(--neo-yellow)', border: '2.5px solid #000', borderRadius: '1.25rem', boxShadow: '4px 4px 0 0 #000', padding: '0 1rem', marginBottom: '1.25rem' }}>
        <SettingsRow icon="🔔" label="Daily Check-in"  desc="Every day at 8:00 PM" toggle on />
        {DIVIDER}
        <SettingsRow icon="⏰" label="Reminder Time"   desc="Tap to change" />
      </div>

      {/* Privacy */}
      <p style={{ fontFamily: 'var(--font-display)', fontWeight: 800, fontSize: '0.7rem', color: '#bbb', letterSpacing: '0.1em', textTransform: 'uppercase', marginBottom: '0.5rem', paddingLeft: '2px' }}>Privacy</p>
      <div style={{ background: '#fff', border: '2.5px solid #000', borderRadius: '1.25rem', boxShadow: '4px 4px 0 0 #000', padding: '0 1rem', marginBottom: '1.5rem' }}>
        <SettingsRow icon="🔐" label="Encryption"       desc="AES-256, on-device" />
        {DIVIDER}
        <SettingsRow icon="👁" label="Data Collection"  desc="Anonymous only" />
        {DIVIDER}
        <SettingsRow icon="📤" label="Export My Data"   desc="Download a copy" />
      </div>

      {/* App info */}
      <div style={{ textAlign: 'center', paddingBottom: '1.5rem' }}>
        <div
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: '0.5rem',
            padding: '0.5rem 1rem',
            border: '2px solid #e5e5e5',
            borderRadius: '9999px',
            marginBottom: '0.5rem',
          }}
        >
          <div
            style={{
              width: '20px',
              height: '20px',
              borderRadius: '4px',
              background: 'var(--neo-blue)',
              border: '1.5px solid #000',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
            }}
          >
            <span style={{ fontFamily: 'var(--font-display)', fontWeight: 800, fontSize: '0.75rem', color: '#fff' }}>K</span>
          </div>
          <span style={{ fontFamily: 'var(--font-display)', fontWeight: 700, fontSize: '0.8rem', color: '#000' }}>KOI</span>
          <span style={{ fontFamily: 'var(--font-body)', fontSize: '0.78rem', color: '#bbb' }}>v1.0.0</span>
        </div>
        <p style={{ fontFamily: 'var(--font-body)', fontSize: '0.75rem', color: '#ccc' }}>
          Made with care · Private by design
        </p>
      </div>
    </div>
  );
}
