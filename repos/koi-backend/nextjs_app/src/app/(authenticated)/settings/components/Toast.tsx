'use client';

import { useEffect } from 'react';

interface ToastProps {
  message: string;
  type?: 'success' | 'error' | 'info';
  onClose: () => void;
  duration?: number;
}

export default function Toast({ message, type = 'info', onClose, duration = 3000 }: ToastProps) {
  useEffect(() => {
    const timer = setTimeout(onClose, duration);
    return () => clearTimeout(timer);
  }, [duration, onClose]);

  const bgColors = {
    success: '#2DD36F',
    error: '#FF4136',
    info: '#2D63EB',
  };

  const icons = {
    success: '✓',
    error: '✗',
    info: 'ℹ',
  };

  return (
    <div
      style={{
        position: 'fixed',
        bottom: '5rem',
        left: '50%',
        transform: 'translateX(-50%)',
        zIndex: 9999,
        animation: 'slideUp 0.3s cubic-bezier(0.34, 1.56, 0.64, 1)',
      }}
    >
      <div
        style={{
          background: bgColors[type],
          color: type === 'success' ? '#000' : '#fff',
          padding: '1rem 1.5rem',
          borderRadius: '12px',
          border: '2.5px solid #000',
          boxShadow: '4px 4px 0 #000',
          display: 'flex',
          alignItems: 'center',
          gap: '0.75rem',
          fontWeight: 700,
          fontSize: '0.9rem',
          maxWidth: '90vw',
        }}
      >
        <span
          style={{
            width: '24px',
            height: '24px',
            borderRadius: '50%',
            background: type === 'success' ? '#000' : '#fff',
            color: type === 'success' ? '#2DD36F' : bgColors[type],
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            fontWeight: 900,
            fontSize: '1rem',
            flexShrink: 0,
          }}
        >
          {icons[type]}
        </span>
        {message}
      </div>
      <style jsx>{`
        @keyframes slideUp {
          from {
            opacity: 0;
            transform: translateX(-50%) translateY(20px);
          }
          to {
            opacity: 1;
            transform: translateX(-50%) translateY(0);
          }
        }
      `}</style>
    </div>
  );
}
