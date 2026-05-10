'use client';

import { useRouter } from 'next/navigation';

export default function BackButton() {
  const router = useRouter();

  return (
    <button
      onClick={() => router.back()}
      className="group"
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        gap: '0.5rem',
        padding: '0.625rem 1rem',
        background: '#fff',
        border: '2.5px solid #000',
        borderRadius: '12px',
        boxShadow: '3px 3px 0 #000',
        cursor: 'pointer',
        fontWeight: 700,
        fontSize: '0.9rem',
        transition: 'all 0.15s ease',
        marginBottom: '1.5rem',
      }}
      onMouseEnter={(e) => {
        e.currentTarget.style.transform = 'translateY(-2px)';
        e.currentTarget.style.boxShadow = '5px 5px 0 #000';
      }}
      onMouseLeave={(e) => {
        e.currentTarget.style.transform = 'translateY(0)';
        e.currentTarget.style.boxShadow = '3px 3px 0 #000';
      }}
      onMouseDown={(e) => {
        e.currentTarget.style.transform = 'translateY(1px)';
        e.currentTarget.style.boxShadow = '1px 1px 0 #000';
      }}
      onMouseUp={(e) => {
        e.currentTarget.style.transform = 'translateY(-2px)';
        e.currentTarget.style.boxShadow = '5px 5px 0 #000';
      }}
    >
      <svg 
        className="transition-transform duration-200 group-hover:-translate-x-1"
        width="16" 
        height="16" 
        viewBox="0 0 24 24" 
        fill="none"
      >
        <path 
          d="M15 18l-6-6 6-6" 
          stroke="#000" 
          strokeWidth="2.5" 
          strokeLinecap="round" 
          strokeLinejoin="round" 
        />
      </svg>
      Back to Settings
    </button>
  );
}
