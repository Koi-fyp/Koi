/** Neutral "K" placeholder shown while auth (or the post-auth redirect) is unresolved. */
export default function AuthPendingSpinner() {
  return (
    <div
      role="status"
      aria-label="Loading KOI"
      data-testid="auth-pending-spinner"
      style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        minHeight: '100svh',
        background: '#ffe5d9',
      }}
    >
      <div
        style={{
          width: '44px',
          height: '44px',
          borderRadius: '10px',
          background: 'var(--neo-blue)',
          border: '2.5px solid #000',
          boxShadow: '4px 4px 0 0 #000',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          animation: 'fadeUp 0.4s ease both',
        }}
      >
        <span
          style={{
            fontFamily: 'var(--font-display)',
            fontWeight: 800,
            fontSize: '1.2rem',
            color: '#fff',
          }}
        >
          K
        </span>
      </div>
    </div>
  );
}
