'use client';

import dynamic from 'next/dynamic';
import { usePathname } from 'next/navigation';
import { useEffect } from 'react';
import type { ReactNode } from 'react';

const APP_FONT_STYLESHEET = 'https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,200..800&family=DM+Sans:ital,opsz,wght@0,9..40,300..700;1,9..40,300..400&display=swap';

// Keep Firebase out of the renderer-only host's runtime module graph. All
// existing application routes continue through the original AuthProvider.
const AuthenticatedApplication = dynamic(
  () => import('./AuthenticatedApplication'),
  { ssr: true },
);

export default function AppAuthBoundary({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const isPresentationOnlyHost = pathname === '/avatar-host' || pathname === '/avatar-host/';
  useEffect(() => {
    if (isPresentationOnlyHost) return;
    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = APP_FONT_STYLESHEET;
    link.dataset.koiApplicationFonts = 'true';
    document.head.appendChild(link);
    return () => link.remove();
  }, [isPresentationOnlyHost]);
  return isPresentationOnlyHost
    ? <>{children}</>
    : <AuthenticatedApplication>{children}</AuthenticatedApplication>;
}
