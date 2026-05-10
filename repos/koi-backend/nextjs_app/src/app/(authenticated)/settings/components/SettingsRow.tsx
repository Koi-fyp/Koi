'use client';

interface RowProps {
  icon: string;
  label: string;
  desc: string;
  danger?: boolean;
  toggle?: boolean;
  on?: boolean;
  onClick?: () => void;
}

export default function SettingsRow({ 
  icon, 
  label, 
  desc, 
  danger = false, 
  toggle = false, 
  on = false,
  onClick 
}: RowProps) {
  return (
    <button
      onClick={onClick}
      className="group"
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
        transition: 'transform 0.15s ease',
      }}
      onMouseEnter={(e) => {
        e.currentTarget.style.transform = 'translateX(4px)';
      }}
      onMouseLeave={(e) => {
        e.currentTarget.style.transform = 'translateX(0)';
      }}
    >
      <span
        className="transition-all duration-200 group-hover:scale-110"
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
        <p style={{ 
          fontWeight: 700, 
          fontSize: '0.9rem', 
          color: danger ? '#FF4136' : '#000',
          transition: 'color 0.2s ease'
        }}>
          {label}
        </p>
        <p style={{ 
          fontSize: '0.78rem', 
          color: '#999', 
          marginTop: '1px',
          transition: 'color 0.2s ease'
        }}>
          {desc}
        </p>
      </div>
      {toggle ? (
        <div
          className="transition-all duration-200"
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
            className="transition-all duration-300"
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
        <svg 
          className="transition-transform duration-200 group-hover:translate-x-1" 
          width="18" 
          height="18" 
          viewBox="0 0 24 24" 
          fill="none"
        >
          <path 
            d="M9 18l6-6-6-6" 
            stroke="#ccc" 
            strokeWidth="2" 
            strokeLinecap="round" 
            strokeLinejoin="round" 
          />
        </svg>
      )}
    </button>
  );
}
