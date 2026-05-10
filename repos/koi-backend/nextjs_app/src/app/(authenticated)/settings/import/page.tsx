'use client';

import BackButton from '../components/BackButton';

export default function ImportPage() {
  return (
    <div style={{ minHeight: '100vh', background: 'linear-gradient(135deg, #F9F9F9 0%, #FAFAFA 100%)' }}>
      <div style={{ padding: '1.5rem', maxWidth: '480px', margin: '0 auto' }}>
        <BackButton />

        {/* Coming Soon Hero */}
        <div
          style={{
            textAlign: 'center',
            padding: '3rem 1rem',
            animation: 'fadeUp 0.6s ease both',
          }}
        >
          <div
            style={{
              fontSize: '5rem',
              marginBottom: '1.5rem',
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
            style={{
              fontSize: '1rem',
              color: '#666',
              lineHeight: 1.7,
              maxWidth: '360px',
              margin: '0 auto 2rem',
              animation: 'fadeUp 0.6s ease 0.3s both',
            }}
          >
            We're building a beautiful way to restore your conversations from PDF and JSON backups.
          </p>
        </div>

        {/* Feature Preview Cards */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem', marginBottom: '2rem' }}>
          {[
            {
              icon: '📄',
              title: 'PDF Import',
              desc: 'Upload exported PDFs and extract your conversations',
              color: '#E3F2FD',
              delay: '0.4s',
            },
            {
              icon: '📊',
              title: 'JSON Import',
              desc: 'Restore complete conversation data from JSON backups',
              color: '#F3E5F5',
              delay: '0.5s',
            },
            {
              icon: '🎯',
              title: 'Smart Conflict Resolution',
              desc: 'Intelligently merge imported data with existing conversations',
              color: '#FFF9C4',
              delay: '0.6s',
            },
            {
              icon: '✓',
              title: 'Preview Before Import',
              desc: 'Review and validate data before adding to your library',
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
            Get Notified
          </h3>
          <p style={{ fontSize: '0.85rem', opacity: 0.9, marginBottom: '1rem', lineHeight: 1.6 }}>
            We'll let you know as soon as import functionality is ready. Stay tuned!
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
            Notify Me (Coming Soon)
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
