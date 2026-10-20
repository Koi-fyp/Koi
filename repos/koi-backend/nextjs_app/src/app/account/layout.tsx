import type { ReactNode } from 'react';
import '../professional/professional.css';
export const metadata = { referrer: 'no-referrer', robots: { index: false, follow: false } };
export default function AccountLayout({ children }: { children: ReactNode }) { return <div className="professional-shell"><header className="professional-header"><a href="/?home=1" className="professional-brand">KOI</a></header><main className="professional-main">{children}</main></div>; }
