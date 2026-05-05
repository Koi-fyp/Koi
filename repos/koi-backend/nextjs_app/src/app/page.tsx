'use client';
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/contexts/AuthContext';
import { isOnboardingComplete } from '@/lib/onboarding';

export default function RootPage() {
  const { user, loading, error, signInAnonymously } = useAuth();
  const router = useRouter();
  const [retrying, setRetrying] = useState(false);

  useEffect(() => {
    if (loading) return;
    if (!user) {
      signInAnonymously().catch(() => {});
      return;
    }
    if (isOnboardingComplete()) {
      router.replace('/chat');
    } else {
      router.replace('/onboarding');
    }
  }, [user, loading]);

  const handleRetry = async () => {
    setRetrying(true);
    try {
      await signInAnonymously();
    } finally {
      setRetrying(false);
    }
  };

  if (error && !user) {
    return (
      <div className="flex flex-col items-center justify-center min-h-screen p-6 gap-4">
        <p className="text-red-500 text-center">
          Failed to initialize. Please check your connection.
        </p>
        <button
          onClick={handleRetry}
          disabled={retrying}
          className="px-6 py-2 bg-[#2E75B6] text-white rounded-xl font-semibold disabled:opacity-50"
        >
          {retrying ? 'Retrying…' : 'Retry'}
        </button>
      </div>
    );
  }

  return (
    <div className="flex items-center justify-center min-h-screen">
      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-[#2E75B6]" />
    </div>
  );
}
