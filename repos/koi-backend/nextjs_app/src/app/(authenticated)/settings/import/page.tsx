'use client';

import BackButton from '../components/BackButton';
import BackupPreview from '@/components/data-portability/BackupPreview';

export default function ImportPage() {
  return (
    <div style={{ minHeight: '100vh', background: 'linear-gradient(135deg, #F9F9F9 0%, #FAFAFA 100%)' }}>
      <div className="mx-auto w-full max-w-6xl p-6 lg:px-8">
        <BackButton />

        {/* Coming Soon Hero */}
        <div
          className="text-center lg:text-left"
          style={{
            padding: '0.5rem 0 1rem',
            animation: 'fadeUp 0.6s ease both',
          }}
        >
          <div
            style={{
              fontSize: '5rem',
              marginBottom: '0.75rem',
              animation: 'floatY 3s ease-in-out infinite',
              filter: 'grayscale(0.3)',
            }}
          >
            📥
          </div>
          
          <h1
            style={{
              fontWeight: 900,
              fontSize: '2.5rem',
              letterSpacing: '-0.03em',
              color: '#000',
              marginBottom: '0.75rem',
              lineHeight: 1.1,
            }}
          >
            Import Data
          </h1>
          
          <div
            style={{
              display: 'inline-block',
              background: 'var(--neo-yellow)',
              border: '2.5px solid #000',
              borderRadius: '12px',
              padding: '0.5rem 1.25rem',
              fontWeight: 800,
              fontSize: '0.9rem',
              boxShadow: '3px 3px 0 #000',
              marginBottom: '1rem',
              animation: 'fadeUp 0.6s ease 0.2s both',
            }}
          >
            ✨ Coming Soon
          </div>

          <p
            className="max-w-3xl mx-auto lg:mx-0"
            style={{
              fontSize: '1rem',
              color: '#666',
              lineHeight: 1.7,
              marginBottom: '0.5rem',
              animation: 'fadeUp 0.6s ease 0.3s both',
            }}
          >
            Only versioned KOI backup JSON is planned for restoration. The read-only preview does not restore records. PDF reports, ordinary JSON and other documents are not restorable backups.
          </p>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-x-8 items-start">
        <div className="min-w-0 [&>section]:mt-0"><BackupPreview /></div>
        <section className="min-w-0" aria-label="Import requirements and limitations">
        {/* Feature Preview Cards */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem', marginBottom: '2rem' }}>
          {[
            {
              icon: '📄',
              title: 'Unsupported files',
              desc: 'PDF, text, CSV and document files cannot restore KOI conversations',
              color: '#E3F2FD',
              delay: '0.4s',
            },
            {
              icon: '📊',
              title: 'KOI JSON Preview',
              desc: 'Validate draft backup structure; encrypted restoration is not enabled',
              color: '#F3E5F5',
              delay: '0.5s',
            },
            {
              icon: '🎯',
              title: 'Duplicate and Conflict Preview',
              desc: 'Compare existing IDs without merging, overwriting or saving records',
              color: '#FFF9C4',
              delay: '0.6s',
            },
            {
              icon: '✓',
              title: 'Existing Key Required',
              desc: 'Matching account metadata does not recover a lost encryption key',
              color: '#E8F5E9',
              delay: '0.7s',
            },
          ].map((feature, i) => (
            <div
              key={i}
              style={{
                background: '#fff',
                border: '2.5px solid #000',
                borderRadius: '1.25rem',
                boxShadow: '4px 4px 0 #000',
                padding: '1.25rem',
                display: 'flex',
                gap: '1rem',
                transition: 'all 0.3s ease',
                opacity: 0.6,
                animation: `fadeUp 0.6s ease ${feature.delay} both`,
              }}
              onMouseEnter={(e) => {
                e.currentTarget.style.boxShadow = '6px 6px 0 #000';
                e.currentTarget.style.transform = 'translateY(-2px)';
                e.currentTarget.style.opacity = '0.8';
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.boxShadow = '4px 4px 0 #000';
                e.currentTarget.style.transform = 'translateY(0)';
                e.currentTarget.style.opacity = '0.6';
              }}
            >
              <div
                style={{
                  width: '56px',
                  height: '56px',
                  background: feature.color,
                  border: '2px solid #000',
                  borderRadius: '12px',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontSize: '1.75rem',
                  flexShrink: 0,
                }}
              >
                {feature.icon}
              </div>
              <div style={{ flex: 1 }}>
                <h3 style={{ fontWeight: 800, fontSize: '1rem', marginBottom: '0.25rem', color: '#333' }}>
                  {feature.title}
                </h3>
                <p style={{ fontSize: '0.85rem', color: '#999', lineHeight: 1.5 }}>
                  {feature.desc}
                </p>
              </div>
            </div>
          ))}
        </div>

        </section>
        </div>

        {/* Notification Card */}
        <div
          style={{
            background: 'linear-gradient(135deg, #2D63EB 0%, #06b6d4 100%)',
            border: '2.5px solid #000',
            borderRadius: '1.5rem',
            boxShadow: '6px 6px 0 rgba(0,0,0,0.3)',
            padding: '1.5rem',
            textAlign: 'center',
            color: '#fff',
            animation: 'fadeUp 0.6s ease 0.8s both',
          }}
        >
          <div style={{ fontSize: '2rem', marginBottom: '0.75rem' }}>🔔</div>
          <h3 style={{ fontWeight: 800, fontSize: '1.1rem', marginBottom: '0.5rem' }}>
            Restoration Not Available
          </h3>
          <p style={{ fontSize: '0.85rem', opacity: 0.9, marginBottom: '1rem', lineHeight: 1.6 }}>
            No notification subscription is registered here. Restoration stays disabled until encrypted validation and safe atomic writes are approved.
          </p>
          <button
            disabled
            style={{
              background: 'rgba(255, 255, 255, 0.2)',
              border: '2px solid rgba(255, 255, 255, 0.4)',
              borderRadius: '12px',
              padding: '0.75rem 1.5rem',
              color: 'rgba(255, 255, 255, 0.6)',
              fontWeight: 700,
              fontSize: '0.9rem',
              cursor: 'not-allowed',
            }}
          >
            Notifications Unavailable
          </button>
        </div>
      </div>

      <style jsx>{`
        @keyframes fadeUp {
          from {
            opacity: 0;
            transform: translateY(20px);
          }
          to {
            opacity: 1;
            transform: translateY(0);
          }
        }
      `}</style>
    </div>
  );
}
