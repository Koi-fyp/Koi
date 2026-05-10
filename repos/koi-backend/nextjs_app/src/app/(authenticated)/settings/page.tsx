'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import SettingsRow from './components/SettingsRow';
import AvatarPicker from './components/AvatarPicker';
import Toast from './components/Toast';

const DIVIDER = <div style={{ height: '1px', background: '#f0f0f0' }} />;

export default function SettingsPage() {
  const router = useRouter();
  const [avatarPickerOpen, setAvatarPickerOpen] = useState(false);
  const [currentAvatar, setCurrentAvatar] = useState('koi');
  const [currentName, setCurrentName] = useState('');
  const [language, setLanguage] = useState<'en' | 'ur'>('en');
  const [notificationsEnabled, setNotificationsEnabled] = useState(true);
  const [toast, setToast] = useState<{ message: string; type: 'success' | 'error' | 'info' } | null>(null);

  const [expandedHelp, setExpandedHelp] = useState<string | null>(null);

  const handleAvatarSave = (avatar: string, name: string) => {
    setCurrentAvatar(avatar);
    setCurrentName(name);
    setToast({ message: 'Companion updated successfully!', type: 'success' });
  };

  const handleLanguageToggle = () => {
    setLanguage(prev => prev === 'en' ? 'ur' : 'en');
    setToast({
      message: language === 'en' ? 'Language changed to Urdu' : 'Language changed to English',
      type: 'info'
    });
  };

  const handleClearHistory = () => {
    setToast({ message: 'All conversations cleared', type: 'success' });
  };

  const handleNotificationToggle = () => {
    setNotificationsEnabled(prev => !prev);
    setToast({
      message: notificationsEnabled ? 'Daily check-in disabled' : 'Daily check-in enabled',
      type: 'info'
    });
  };

  const toggleHelp = (section: string) => {
    setExpandedHelp(prev => prev === section ? null : section);
  };

  const getAvatarDisplay = () => {
    const avatars: Record<string, string> = {
      aisha: 'Aisha 👩',
      raza: 'Raza 👨',
      koi: 'Koi 🦊'
    };
    return avatars[currentAvatar] || 'Koi 🦊';
  };

  return (
    <>
      <div style={{ padding: '1.5rem 1.5rem 0', maxWidth: '480px', margin: '0 auto' }}>
        <h1
          style={{
            fontWeight: 900,
            fontSize: '2rem',
            letterSpacing: '-0.03em',
            color: '#000',
            marginBottom: '1.5rem',
          }}
        >
          Settings
        </h1>

        {/* Account */}
        <p style={{
          fontWeight: 800,
          fontSize: '0.7rem',
          color: '#bbb',
          letterSpacing: '0.1em',
          textTransform: 'uppercase',
          marginBottom: '0.5rem',
          paddingLeft: '2px'
        }}>
          Account
        </p>
        <div
          className="settings-card"
          style={{
            background: '#fff',
            border: '2.5px solid #000',
            borderRadius: '1.25rem',
            boxShadow: '4px 4px 0 0 #000',
            padding: '0 1rem',
            marginBottom: '1.25rem',
            transition: 'all 0.2s ease',
          }}
          onMouseEnter={(e) => {
            e.currentTarget.style.boxShadow = '6px 6px 0 0 #000';
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.boxShadow = '4px 4px 0 0 #000';
          }}
        >
          <SettingsRow
            icon="👤"
            label="Avatar & Name"
            desc={getAvatarDisplay()}
            onClick={() => setAvatarPickerOpen(true)}
          />
          {DIVIDER}
          <SettingsRow
            icon="🌐"
            label="Language"
            desc={language === 'en' ? 'English' : 'Urdu'}
            onClick={handleLanguageToggle}
          />
          {DIVIDER}
          <SettingsRow
            icon="🗑"
            label="Clear History"
            desc="Delete all conversations"
            danger
            onClick={handleClearHistory}
          />
        </div>

        {/* Notifications — yellow card */}
        <p style={{
          fontWeight: 800,
          fontSize: '0.7rem',
          color: '#bbb',
          letterSpacing: '0.1em',
          textTransform: 'uppercase',
          marginBottom: '0.5rem',
          paddingLeft: '2px'
        }}>
          Notifications
        </p>
        <div
          className="settings-card"
          style={{
            background: 'var(--neo-yellow)',
            border: '2.5px solid #000',
            borderRadius: '1.25rem',
            boxShadow: '4px 4px 0 0 #000',
            padding: '0 1rem',
            marginBottom: '1.25rem',
            transition: 'all 0.2s ease',
          }}
          onMouseEnter={(e) => {
            e.currentTarget.style.boxShadow = '6px 6px 0 0 #000';
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.boxShadow = '4px 4px 0 0 #000';
          }}
        >
          <SettingsRow
            icon="🔔"
            label="Daily Check-in"
            desc={notificationsEnabled ? "Every day at 8:00 PM" : "Disabled"}
            toggle
            on={notificationsEnabled}
            onClick={handleNotificationToggle}
          />
          {DIVIDER}
          <SettingsRow
            icon="⏰"
            label="Reminder Time"
            desc="Tap to change"
            onClick={() => setToast({ message: 'Time picker coming soon!', type: 'info' })}
          />
        </div>

        {/* Privacy */}
        <p style={{
          fontWeight: 800,
          fontSize: '0.7rem',
          color: '#bbb',
          letterSpacing: '0.1em',
          textTransform: 'uppercase',
          marginBottom: '0.5rem',
          paddingLeft: '2px'
        }}>
          Privacy
        </p>
        <div
          className="settings-card"
          style={{
            background: '#fff',
            border: '2.5px solid #000',
            borderRadius: '1.25rem',
            boxShadow: '4px 4px 0 0 #000',
            padding: '0 1rem',
            marginBottom: '1.25rem',
            transition: 'all 0.2s ease',
          }}
          onMouseEnter={(e) => {
            e.currentTarget.style.boxShadow = '6px 6px 0 0 #000';
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.boxShadow = '4px 4px 0 0 #000';
          }}
        >
          <SettingsRow
            icon="🔐"
            label="Encryption"
            desc="AES-256, on-device"
            onClick={() => router.push('/settings/privacy')}
          />
          {DIVIDER}
          <SettingsRow
            icon="👁"
            label="Data Collection"
            desc="Anonymous only"
            onClick={() => router.push('/settings/privacy')}
          />
          {DIVIDER}
          <SettingsRow
            icon="📤"
            label="Export My Data"
            desc="Download a copy"
            onClick={() => router.push('/settings/export')}
          />
          {DIVIDER}
          <SettingsRow
            icon="📥"
            label="Import Data"
            desc="Restore from backup"
            onClick={() => router.push('/settings/import')}
          />
        </div>

        {/* Storage */}
        <p style={{
          fontWeight: 800,
          fontSize: '0.7rem',
          color: '#bbb',
          letterSpacing: '0.1em',
          textTransform: 'uppercase',
          marginBottom: '0.5rem',
          paddingLeft: '2px'
        }}>
          Storage
        </p>
        <div
          className="settings-card"
          style={{
            background: '#fff',
            border: '2.5px solid #000',
            borderRadius: '1.25rem',
            boxShadow: '4px 4px 0 0 #000',
            padding: '1.25rem',
            marginBottom: '1.25rem',
            transition: 'all 0.2s ease',
          }}
          onMouseEnter={(e) => {
            e.currentTarget.style.boxShadow = '6px 6px 0 0 #000';
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.boxShadow = '4px 4px 0 0 #000';
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: '1rem' }}>
            {/* Circular progress */}
            <div style={{ position: 'relative', width: '80px', height: '80px', flexShrink: 0 }}>
              <svg width="80" height="80" viewBox="0 0 80 80" style={{ transform: 'rotate(-90deg)' }}>
                {/* Background circle */}
                <circle
                  cx="40"
                  cy="40"
                  r="32"
                  fill="none"
                  stroke="#F0F0F0"
                  strokeWidth="8"
                />
                {/* Progress circle */}
                <circle
                  cx="40"
                  cy="40"
                  r="32"
                  fill="none"
                  stroke="#2D63EB"
                  strokeWidth="8"
                  strokeDasharray={`${2.01 * Math.PI * 32} ${200.96 * Math.PI * 32}`}
                  strokeLinecap="round"
                  style={{ transition: 'stroke-dasharray 0.3s ease' }}
                />
              </svg>
              <div
                style={{
                  position: 'absolute',
                  inset: 0,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontWeight: 900,
                  fontSize: '1.25rem',
                  color: '#000'
                }}
              >
                1%
              </div>
            </div>

            <div style={{ flex: 1 }}>
              <p style={{ fontWeight: 700, fontSize: '0.95rem', color: '#000', marginBottom: '0.25rem' }}>
                Local Storage
              </p>
              <p style={{ fontSize: '0.8rem', color: '#666' }}>
                42 KB of 5 MB used
              </p>
              <div
                style={{
                  marginTop: '0.75rem',
                  height: '6px',
                  background: '#F0F0F0',
                  borderRadius: '3px',
                  overflow: 'hidden',
                  border: '1px solid #ddd'
                }}
              >
                <div
                  style={{
                    height: '100%',
                    width: '1%',
                    background: 'linear-gradient(90deg, #2D63EB 0%, #06b6d4 100%)',
                    transition: 'width 0.3s ease'
                  }}
                />
              </div>
            </div>
          </div>
        </div>

        {/* About & Help */}
        <p style={{
          fontWeight: 800,
          fontSize: '0.7rem',
          color: '#bbb',
          letterSpacing: '0.1em',
          textTransform: 'uppercase',
          marginBottom: '0.5rem',
          paddingLeft: '2px'
        }}>
          About & Help
        </p>
        <div
          className="settings-card"
          style={{
            background: '#fff',
            border: '2.5px solid #000',
            borderRadius: '1.25rem',
            boxShadow: '4px 4px 0 0 #000',
            padding: '0 1rem',
            marginBottom: '1.5rem',
            transition: 'all 0.2s ease',
          }}
          onMouseEnter={(e) => {
            e.currentTarget.style.boxShadow = '6px 6px 0 0 #000';
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.boxShadow = '4px 4px 0 0 #000';
          }}
        >
          {/* Version Info */}
          <button
            onClick={() => toggleHelp('version')}
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
            }}
          >
            <span style={{
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
            }}>
              ℹ️
            </span>
            <div style={{ flex: 1 }}>
              <p style={{ fontWeight: 700, fontSize: '0.9rem', color: '#000' }}>
                Version Info
              </p>
              <p style={{ fontSize: '0.78rem', color: '#999', marginTop: '1px' }}>
                KOI v1.0.0
              </p>
            </div>
            <svg
              style={{
                transform: expandedHelp === 'version' ? 'rotate(180deg)' : 'rotate(0deg)',
                transition: 'transform 0.3s ease'
              }}
              width="18"
              height="18"
              viewBox="0 0 24 24"
              fill="none"
            >
              <path d="M6 9l6 6 6-6" stroke="#ccc" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </button>

          <div
            style={{
              maxHeight: expandedHelp === 'version' ? '200px' : '0',
              overflow: 'hidden',
              transition: 'max-height 0.3s ease',
            }}
          >
            <div style={{
              padding: '0 0 1rem 3.375rem',
              fontSize: '0.85rem',
              color: '#666',
              lineHeight: '1.6'
            }}>
              <p style={{ marginBottom: '0.5rem' }}>
                <strong>Release Date:</strong> January 2025
              </p>
              <p style={{ marginBottom: '0.5rem' }}>
                <strong>Build:</strong> Production
              </p>
              <p>
                <strong>Platform:</strong> Web App
              </p>
            </div>
          </div>

          {DIVIDER}

          {/* What's New */}
          <button
            onClick={() => toggleHelp('whatsnew')}
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
            }}
          >
            <span style={{
              width: '38px',
              height: '38px',
              borderRadius: '8px',
              background: 'var(--neo-yellow)',
              border: '2px solid #000',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              fontSize: '1.1rem',
              flexShrink: 0,
            }}>
              ✨
            </span>
            <div style={{ flex: 1 }}>
              <p style={{ fontWeight: 700, fontSize: '0.9rem', color: '#000' }}>
                What's New
              </p>
              <p style={{ fontSize: '0.78rem', color: '#999', marginTop: '1px' }}>
                Latest updates & features
              </p>
            </div>
            <svg
              style={{
                transform: expandedHelp === 'whatsnew' ? 'rotate(180deg)' : 'rotate(0deg)',
                transition: 'transform 0.3s ease'
              }}
              width="18"
              height="18"
              viewBox="0 0 24 24"
              fill="none"
            >
              <path d="M6 9l6 6 6-6" stroke="#ccc" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </button>

          <div
            style={{
              maxHeight: expandedHelp === 'whatsnew' ? '300px' : '0',
              overflow: 'hidden',
              transition: 'max-height 0.3s ease',
            }}
          >
            <div style={{
              padding: '0 0 1rem 3.375rem',
              fontSize: '0.85rem',
              color: '#666',
              lineHeight: '1.6'
            }}>
              <p style={{ marginBottom: '0.75rem', fontWeight: 600, color: '#000' }}>
                🎉 v1.0.0 Release
              </p>
              <ul style={{ paddingLeft: '1.25rem', margin: 0 }}>
                <li style={{ marginBottom: '0.5rem' }}>Enhanced avatar animations</li>
                <li style={{ marginBottom: '0.5rem' }}>Improved offline support</li>
                <li style={{ marginBottom: '0.5rem' }}>New privacy controls</li>
                <li>Performance optimizations</li>
              </ul>
            </div>
          </div>

          {DIVIDER}

          {/* Crisis Resources */}
          <button
            onClick={() => toggleHelp('crisis')}
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
            }}
          >
            <span style={{
              width: '38px',
              height: '38px',
              borderRadius: '8px',
              background: '#FF4A60',
              border: '2px solid #000',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              fontSize: '1.1rem',
              flexShrink: 0,
              color: '#fff'
            }}>
              🆘
            </span>
            <div style={{ flex: 1 }}>
              <p style={{ fontWeight: 700, fontSize: '0.9rem', color: '#000' }}>
                Crisis Resources
              </p>
              <p style={{ fontSize: '0.78rem', color: '#999', marginTop: '1px' }}>
                24/7 helplines (Pakistan)
              </p>
            </div>
            <svg
              style={{
                transform: expandedHelp === 'crisis' ? 'rotate(180deg)' : 'rotate(0deg)',
                transition: 'transform 0.3s ease'
              }}
              width="18"
              height="18"
              viewBox="0 0 24 24"
              fill="none"
            >
              <path d="M6 9l6 6 6-6" stroke="#ccc" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </button>

          <div
            style={{
              maxHeight: expandedHelp === 'crisis' ? '300px' : '0',
              overflow: 'hidden',
              transition: 'max-height 0.3s ease',
            }}
          >
            <div style={{
              padding: '0 0 1rem 3.375rem',
              fontSize: '0.85rem',
              color: '#666',
              lineHeight: '1.6'
            }}>
              <div style={{ marginBottom: '0.75rem' }}>
                <p style={{ fontWeight: 600, color: '#000', marginBottom: '0.25rem' }}>
                  Umang (Mental Health)
                </p>
                <a href="tel:03117786264" style={{ color: '#FF4A60', fontWeight: 700, textDecoration: 'none' }}>
                  0311-7786264
                </a>
              </div>
              <div style={{ marginBottom: '0.75rem' }}>
                <p style={{ fontWeight: 600, color: '#000', marginBottom: '0.25rem' }}>
                  Rozan Counselling
                </p>
                <a href="tel:080022444" style={{ color: '#FF4A60', fontWeight: 700, textDecoration: 'none' }}>
                  0800-22444
                </a>
              </div>
              <div>
                <p style={{ fontWeight: 600, color: '#000', marginBottom: '0.25rem' }}>
                  Emergency Services
                </p>
                <a href="tel:15" style={{ color: '#FF4A60', fontWeight: 700, textDecoration: 'none' }}>
                  15 / 1122
                </a>
              </div>
            </div>
          </div>
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
              <span style={{ fontWeight: 800, fontSize: '0.75rem', color: '#fff' }}>K</span>
            </div>
            <span style={{ fontWeight: 700, fontSize: '0.8rem', color: '#000' }}>KOI</span>
            <span style={{ fontSize: '0.78rem', color: '#bbb' }}>v1.0.0</span>
          </div>
          <p style={{ fontSize: '0.75rem', color: '#ccc' }}>
            Made with care · Private by design
          </p>
        </div>
      </div>

      {/* Avatar Picker Modal */}
      <AvatarPicker
        isOpen={avatarPickerOpen}
        onClose={() => setAvatarPickerOpen(false)}
        currentAvatar={currentAvatar}
        currentName={currentName}
        onSave={handleAvatarSave}
      />

      {/* Toast Notifications */}
      {toast && (
        <Toast
          message={toast.message}
          type={toast.type}
          onClose={() => setToast(null)}
        />
      )}
    </>
  );
}
