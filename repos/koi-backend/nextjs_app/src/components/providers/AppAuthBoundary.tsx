'use client';

import dynamic from 'next/dynamic';
import { usePathname } from 'next/navigation';
import type { ReactNode } from 'react';

// Keep Firebase out of the renderer-only host's runtime module graph. All
// existing application routes continue through the original AuthProvider.
const AuthenticatedApplication = dynamic(
  () => import('./AuthenticatedApplication'),
  { ssr: true },
);

export default function AppAuthBoundary({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const isPresentationOnlyHost = pathname === '/avatar-host' || pathname === '/avatar-host/';
  return isPresentationOnlyHost
    ? <>{children}</>
    : <AuthenticatedApplication>{children}</AuthenticatedApplication>;
}
