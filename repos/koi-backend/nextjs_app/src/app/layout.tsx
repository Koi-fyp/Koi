import type { Metadata } from 'next';
import './globals.css';
import AppAuthBoundary from '@/components/providers/AppAuthBoundary';

export const metadata: Metadata = {
  title: 'KOI — Your AI Companion',
  description: 'An AI companion for text conversation with Firebase anonymous sign-in and encrypted local history. Not a substitute for professional care.',
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
