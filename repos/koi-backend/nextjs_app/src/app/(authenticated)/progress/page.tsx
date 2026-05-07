const STATS = [
  { label: 'Days Streak',    value: '12',  unit: 'days',     color: 'var(--neo-yellow)' },
  { label: 'Total Sessions', value: '47',  unit: 'sessions', color: 'var(--neo-mint)'   },
  { label: 'Avg Mood',       value: '7.2', unit: '/ 10',     color: 'var(--neo-blue)'   },
];

const MILESTONES = [
  { id: 1, title: 'First Conversation', desc: 'You opened up for the first time.',   done: true,  color: 'var(--neo-mint)'   },
  { id: 2, title: '7-Day Streak',       desc: 'A week of showing up for yourself.',  done: true,  color: 'var(--neo-blue)'   },
  { id: 3, title: '50 Pieces',          desc: 'Halfway to your first milestone.',    done: false, color: 'var(--neo-yellow)' },
  { id: 4, title: 'Deep Diver',         desc: 'Explored something truly personal.',  done: false, color: 'var(--neo-purple)' },
];

export default function ProgressPage() {
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
        Your Progress
      </h1>

      {/* Hero stat */}
      <div
        style={{
          background: 'var(--neo-blue)',
          border: '2.5px solid #000',
          borderRadius: '1.25rem',
          boxShadow: '6px 6px 0 0 #000',
          padding: '1.5rem',
          marginBottom: '1.25rem',
          position: 'relative',
          overflow: 'hidden',
        }}
      >
        <p style={{ fontFamily: 'var(--font-body)', fontSize: '0.75rem', color: 'rgba(255,255,255,0.65)', fontWeight: 500, marginBottom: '0.375rem', letterSpacing: '0.08em', textTransform: 'uppercase' }}>
          Total Pieces Collected
        </p>
        <p style={{ fontFamily: 'var(--font-display)', fontWeight: 800, fontSize: '3.5rem', color: '#fff', lineHeight: 1, letterSpacing: '-0.03em', marginBottom: '0.25rem' }}>
          🧩 247
        </p>
        <p style={{ fontFamily: 'var(--font-body)', fontSize: '0.875rem', color: 'rgba(255,255,255,0.6)' }}>
          pieces of your story, preserved
        </p>
        <div style={{ position: 'absolute', right: '-1.5rem', top: '-1.5rem', width: '8rem', height: '8rem', borderRadius: '50%', background: 'rgba(255,255,255,0.07)', border: '2px solid rgba(255,255,255,0.1)' }} />
      </div>

      {/* Stats grid */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '10px', marginBottom: '1.25rem' }}>
        {STATS.map((stat) => (
          <div
            key={stat.label}
            style={{
              background: '#fff',
              border: '2.5px solid #000',
              borderRadius: '1rem',
              boxShadow: '4px 4px 0 0 #000',
              padding: '0.875rem 0.75rem',
              textAlign: 'center',
            }}
          >
            <div style={{ width: '8px', height: '8px', borderRadius: '50%', background: stat.color, border: '1.5px solid #000', margin: '0 auto 0.5rem' }} />
            <p style={{ fontFamily: 'var(--font-display)', fontWeight: 800, fontSize: '1.3rem', color: '#000', lineHeight: 1 }}>{stat.value}</p>
            <p style={{ fontFamily: 'var(--font-body)', fontSize: '0.62rem', color: '#aaa', marginTop: '2px', fontWeight: 500, textTransform: 'uppercase', letterSpacing: '0.06em' }}>{stat.unit}</p>
            <p style={{ fontFamily: 'var(--font-body)', fontSize: '0.68rem', color: '#666', marginTop: '2px', fontWeight: 500 }}>{stat.label}</p>
          </div>
        ))}
      </div>

      {/* Milestone timeline */}
      <div
        style={{
          background: '#fff',
          border: '2.5px solid #000',
          borderRadius: '1.25rem',
          boxShadow: '6px 6px 0 0 #000',
          padding: '1.25rem',
          marginBottom: '1.5rem',
        }}
      >
        <h2 style={{ fontFamily: 'var(--font-display)', fontWeight: 800, fontSize: '1.1rem', color: '#000', marginBottom: '1.1rem', letterSpacing: '-0.02em' }}>
          Milestones
        </h2>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '0.875rem' }}>
          {MILESTONES.map((m, i) => (
            <div key={m.id} style={{ display: 'flex', gap: '0.875rem', alignItems: 'flex-start', opacity: m.done ? 1 : 0.5 }}>
              <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', flexShrink: 0, paddingTop: '2px' }}>
                <div
                  style={{
                    width: '20px',
                    height: '20px',
                    borderRadius: '4px',
                    background: m.done ? m.color : '#eee',
                    border: '2px solid #000',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    flexShrink: 0,
                  }}
                >
                  {m.done && (
                    <svg width="11" height="11" viewBox="0 0 12 12" fill="none">
                      <path d="M2 6l3 3 5-5" stroke="#000" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
                    </svg>
                  )}
                </div>
                {i < MILESTONES.length - 1 && (
                  <div style={{ width: '2px', flex: '1 0 16px', background: '#eee', marginTop: '3px' }} />
                )}
              </div>
              <div>
                <p style={{ fontFamily: 'var(--font-display)', fontWeight: 700, fontSize: '0.875rem', color: '#000', marginBottom: '2px' }}>{m.title}</p>
                <p style={{ fontFamily: 'var(--font-body)', fontSize: '0.78rem', color: '#777', lineHeight: 1.4 }}>{m.desc}</p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
