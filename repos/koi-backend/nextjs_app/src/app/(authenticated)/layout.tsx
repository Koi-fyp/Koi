'use client';
import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/contexts/AuthContext';
import BottomNav from '@/components/layout/BottomNav';
import AuthPendingSpinner from '@/components/layout/AuthPendingSpinner';
import ConversationProvider from '@/contexts/ConversationContext';
import { InputModeProvider } from '@/contexts/InputModeContext';

export default function AuthenticatedLayout({ children }: { children: React.ReactNode }) {
  const { user, loading } = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (!loading && !user) {
      router.replace('/');
    }
  }, [user, loading, router]);

  if (loading || !user) {
    return <AuthPendingSpinner />;
  }

  return (
    <InputModeProvider>
      <div style={{ display: 'flex', flexDirection: 'column', minHeight: '100svh', paddingTop: '66px' }}>
        <BottomNav />
        <main style={{ flex: 1 }}><ConversationProvider>{children}</ConversationProvider></main>
      </div>
    </InputModeProvider>
  );
}
