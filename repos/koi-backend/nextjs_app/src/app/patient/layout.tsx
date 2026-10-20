import PlatformNavigation from '@/components/platform/PlatformNavigation';
import type { ReactNode } from 'react';
import '../professional/professional.css';
export const metadata = { referrer: 'no-referrer', robots: { index: false, follow: false } };
export default function PatientLayout({ children }: { children: ReactNode }) {
  return <div className="professional-shell"><header className="professional-header"><a className="professional-brand" href="/">KOI<span className="professional-muted"> / Your care</span></a><PlatformNavigation /></header><main className="professional-main">{children}</main></div>;
}
