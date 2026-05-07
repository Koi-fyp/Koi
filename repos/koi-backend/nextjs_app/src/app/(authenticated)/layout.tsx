'use client';
import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/contexts/AuthContext';
import BottomNav from '@/components/layout/BottomNav';

export default function AuthenticatedLayout({ children }: { children: React.ReactNode }) {
  const { user, loading } = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (!loading && !user) {
      router.replace('/');
    }
  }, [user, loading, router]);

  if (loading || !user) {
    return (
      <div
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

  return (
    <div style={{ display: 'flex', flexDirection: 'column', minHeight: '100svh', paddingTop: '66px' }}>
      <BottomNav />
      <main style={{ flex: 1 }}>{children}</main>
    </div>
  );
}
