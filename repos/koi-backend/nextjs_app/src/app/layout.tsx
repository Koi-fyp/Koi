import type { Metadata } from 'next';
import './globals.css';
import AppAuthBoundary from '@/components/providers/AppAuthBoundary';

export const metadata: Metadata = {
  title: 'KOI — Your AI Companion',
  description: 'A thoughtful AI friend that listens, remembers, and grows with you. Start a conversation in seconds — no account needed.',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="font-inter">
      <body className="min-h-screen">
        <AppAuthBoundary>{children}</AppAuthBoundary>
      </body>
    </html>
  );
}
