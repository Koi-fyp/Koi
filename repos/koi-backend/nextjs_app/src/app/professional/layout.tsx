import PlatformNavigation from '@/components/platform/PlatformNavigation';
import type { ReactNode } from 'react';
import './professional.css';
export default function ProfessionalLayout({ children }: { children: ReactNode }) {
  return <div className="professional-shell"><header className="professional-header"><a className="professional-brand" href="/">KOI<span className="professional-muted"> / Professional</span></a><span className="professional-badge">Your practice</span><PlatformNavigation /></header><main className="professional-main">{children}</main></div>;
}
