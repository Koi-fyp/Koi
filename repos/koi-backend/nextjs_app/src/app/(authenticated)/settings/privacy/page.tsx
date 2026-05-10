'use client';

import { useState, useEffect } from 'react';
import BackButton from '../components/BackButton';

export default function PrivacyPage() {
  const [scrollY, setScrollY] = useState(0);

  useEffect(() => {
    const handleScroll = () => setScrollY(window.scrollY);
    window.addEventListener('scroll', handleScroll);
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  const getParallaxStyle = (speed: number) => ({
    transform: `translateY(${scrollY * speed}px)`,
    transition: 'transform 0.1s ease-out',
  });

  return (
    <div style={{ minHeight: '100vh', background: '#FAFAFA' }}>
      <div style={{ padding: '1.5rem', maxWidth: '480px', margin: '0 auto' }}>
        <BackButton />

        {/* Hero Section */}
        <div style={{ marginBottom: '2rem', ...getParallaxStyle(0.05) }}>
          <div
            style={{
              fontSize: '3rem',
              marginBottom: '1rem',
              animation: 'floatY 3s ease-in-out infinite',
            }}
          >
            🔐
          </div>
          <h1
            style={{
              fontWeight: 900,
              fontSize: '2.25rem',
              letterSpacing: '-0.03em',
              color: '#000',
              marginBottom: '0.5rem',
              lineHeight: 1.2,
            }}
          >
            Privacy Center
          </h1>
          <p style={{ fontSize: '0.95rem', color: '#666', lineHeight: 1.6 }}>
            Your data, your control. Here's everything we do to keep your conversations private.
          </p>
        </div>

        {/* Encryption Status */}
        <div
          style={{
            background: '#fff',
            border: '2.5px solid #000',
            borderRadius: '1.5rem',
            boxShadow: '6px 6px 0 #000',
            padding: '1.5rem',
            marginBottom: '1.5rem',
            ...getParallaxStyle(0.02),
            transition: 'all 0.3s ease',
          }}
          onMouseEnter={(e) => {
            e.currentTarget.style.boxShadow = '8px 8px 0 #000';
            e.currentTarget.style.transform = `translateY(${scrollY * 0.02 - 2}px)`;
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.boxShadow = '6px 6px 0 #000';
            e.currentTarget.style.transform = `translateY(${scrollY * 0.02}px)`;
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: '1rem', marginBottom: '1.25rem' }}>
            <div
              style={{
                width: '48px',
                height: '48px',
                background: '#2DD36F',
                border: '2.5px solid #000',
                borderRadius: '12px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontSize: '1.5rem',
                flexShrink: 0,
              }}
            >
              ✓
            </div>
            <div>
              <h3 style={{ fontWeight: 800, fontSize: '1.1rem', marginBottom: '0.25rem' }}>
                Encryption Active
              </h3>
              <p style={{ fontSize: '0.85rem', color: '#666' }}>
                AES-256 • Military-grade
              </p>
            </div>
          </div>

          <div
            style={{
              background: '#F9F9F9',
              border: '2px solid #E5E5E5',
              borderRadius: '12px',
              padding: '1rem',
            }}
          >
            <p style={{ fontSize: '0.85rem', color: '#333', lineHeight: 1.6, margin: 0 }}>
              All your conversations are encrypted on your device before being stored. 
              Not even we can read them — your data stays completely private.
            </p>
          </div>
        </div>

        {/* Data Breakdown */}
        <div
          style={{
            background: '#fff',
            border: '2.5px solid #000',
            borderRadius: '1.5rem',
            boxShadow: '6px 6px 0 #000',
            padding: '1.5rem',
            marginBottom: '1.5rem',
            ...getParallaxStyle(0.03),
          }}
        >
          <h3 style={{ fontWeight: 800, fontSize: '1.1rem', marginBottom: '1.25rem' }}>
            📊 What We Store
          </h3>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
            {/* Local Storage */}
            <div
              style={{
                padding: '1rem',
                background: 'linear-gradient(135deg, #E3F2FD 0%, #F3E5F5 100%)',
                border: '2px solid #000',
                borderRadius: '12px',
                transition: 'transform 0.2s ease',
              }}
              onMouseEnter={(e) => e.currentTarget.style.transform = 'translateX(4px)'}
              onMouseLeave={(e) => e.currentTarget.style.transform = 'translateX(0)'}
            >
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '0.5rem' }}>
                <span style={{ fontWeight: 700, fontSize: '0.9rem' }}>📱 On Your Device</span>
                <span
                  style={{
                    background: '#2D63EB',
                    color: '#fff',
                    padding: '0.25rem 0.75rem',
                    borderRadius: '12px',
                    fontSize: '0.75rem',
                    fontWeight: 700,
                    border: '1.5px solid #000',
                  }}
                >
                  Encrypted
                </span>
              </div>
              <ul style={{ margin: 0, paddingLeft: '1.25rem', fontSize: '0.8rem', color: '#333', lineHeight: 1.6 }}>
                <li>All conversation messages</li>
                <li>Your preferences & settings</li>
                <li>Avatar choice</li>
              </ul>
            </div>

            {/* Cloud Backup */}
            <div
              style={{
                padding: '1rem',
                background: 'linear-gradient(135deg, #FFF9C4 0%, #FFE0B2 100%)',
                border: '2px solid #000',
                borderRadius: '12px',
                transition: 'transform 0.2s ease',
              }}
              onMouseEnter={(e) => e.currentTarget.style.transform = 'translateX(4px)'}
              onMouseLeave={(e) => e.currentTarget.style.transform = 'translateX(0)'}
            >
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '0.5rem' }}>
                <span style={{ fontWeight: 700, fontSize: '0.9rem' }}>☁️ Cloud (Optional)</span>
                <span
                  style={{
                    background: '#FFD100',
                    color: '#000',
                    padding: '0.25rem 0.75rem',
                    borderRadius: '12px',
                    fontSize: '0.75rem',
                    fontWeight: 700,
                    border: '1.5px solid #000',
                  }}
                >
                  Anonymous
                </span>
              </div>
              <ul style={{ margin: 0, paddingLeft: '1.25rem', fontSize: '0.8rem', color: '#333', lineHeight: 1.6 }}>
                <li>Session ID only (no personal info)</li>
                <li>Usage statistics</li>
                <li>Crash reports</li>
              </ul>
            </div>

            {/* Never Stored */}
            <div
              style={{
                padding: '1rem',
                background: 'linear-gradient(135deg, #FFEBEE 0%, #FCE4EC 100%)',
                border: '2px solid #000',
                borderRadius: '12px',
                transition: 'transform 0.2s ease',
              }}
              onMouseEnter={(e) => e.currentTarget.style.transform = 'translateX(4px)'}
              onMouseLeave={(e) => e.currentTarget.style.transform = 'translateX(0)'}
            >
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '0.5rem' }}>
                <span style={{ fontWeight: 700, fontSize: '0.9rem' }}>🚫 Never Stored</span>
                <span
                  style={{
                    background: '#FF4A60',
                    color: '#fff',
                    padding: '0.25rem 0.75rem',
                    borderRadius: '12px',
                    fontSize: '0.75rem',
                    fontWeight: 700,
                    border: '1.5px solid #000',
                  }}
                >
                  Protected
                </span>
              </div>
              <ul style={{ margin: 0, paddingLeft: '1.25rem', fontSize: '0.8rem', color: '#333', lineHeight: 1.6 }}>
                <li>Your real name or email</li>
                <li>Location data</li>
                <li>Payment information</li>
                <li>Shared with third parties</li>
              </ul>
            </div>
          </div>
        </div>

        {/* Audit Log */}
        <div
          style={{
            background: '#fff',
            border: '2.5px solid #000',
            borderRadius: '1.5rem',
            boxShadow: '6px 6px 0 #000',
            padding: '1.5rem',
            marginBottom: '1.5rem',
            ...getParallaxStyle(0.01),
          }}
        >
          <h3 style={{ fontWeight: 800, fontSize: '1.1rem', marginBottom: '1.25rem' }}>
            📝 Recent Activity
          </h3>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
            {[
              { action: 'Conversation saved', time: '2 minutes ago', icon: '💬' },
              { action: 'Settings updated', time: '1 hour ago', icon: '⚙️' },
              { action: 'Data synced', time: '3 hours ago', icon: '🔄' },
              { action: 'Avatar changed', time: 'Yesterday', icon: '👤' },
            ].map((log, i) => (
              <div
                key={i}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: '0.75rem',
                  padding: '0.75rem',
                  background: '#F9F9F9',
                  border: '1.5px solid #E5E5E5',
                  borderRadius: '10px',
                  transition: 'all 0.2s ease',
                  animation: `slideRight 0.3s ease ${i * 0.1}s both`,
                }}
                onMouseEnter={(e) => {
                  e.currentTarget.style.background = '#F0F0F0';
                  e.currentTarget.style.transform = 'translateX(4px)';
                }}
                onMouseLeave={(e) => {
                  e.currentTarget.style.background = '#F9F9F9';
                  e.currentTarget.style.transform = 'translateX(0)';
                }}
              >
                <span style={{ fontSize: '1.25rem' }}>{log.icon}</span>
                <div style={{ flex: 1 }}>
                  <p style={{ fontSize: '0.85rem', fontWeight: 600, marginBottom: '0.15rem' }}>
                    {log.action}
                  </p>
                  <p style={{ fontSize: '0.75rem', color: '#999' }}>
                    {log.time}
                  </p>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Delete Account */}
        <div
          style={{
            background: 'linear-gradient(135deg, #FFEBEE 0%, #FCE4EC 100%)',
            border: '2.5px solid #FF4136',
            borderRadius: '1.5rem',
            boxShadow: '6px 6px 0 rgba(255, 65, 54, 0.3)',
            padding: '1.5rem',
            marginBottom: '2rem',
            ...getParallaxStyle(0.015),
          }}
        >
          <div style={{ display: 'flex', gap: '1rem', marginBottom: '1rem' }}>
            <span style={{ fontSize: '2rem', flexShrink: 0 }}>⚠️</span>
            <div>
              <h3 style={{ fontWeight: 800, fontSize: '1.1rem', marginBottom: '0.5rem', color: '#FF4136' }}>
                Danger Zone
              </h3>
              <p style={{ fontSize: '0.85rem', color: '#666', lineHeight: 1.6 }}>
                Deleting your account will permanently remove all your data from our servers. 
                This action cannot be undone.
              </p>
            </div>
          </div>
          <button
            className="neo-btn-ghost"
            style={{
              width: '100%',
              borderColor: '#FF4136',
              color: '#FF4136',
              boxShadow: '0 3px 0 0 #FF4136',
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.background = '#FF4136';
              e.currentTarget.style.color = '#fff';
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.background = 'transparent';
              e.currentTarget.style.color = '#FF4136';
            }}
          >
            Delete My Account
          </button>
        </div>
      </div>
    </div>
  );
}
