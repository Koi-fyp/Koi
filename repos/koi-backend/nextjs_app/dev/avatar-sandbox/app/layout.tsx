import type { ReactNode } from 'react';
import { notFound } from 'next/navigation';
import './sandbox.css';

export const metadata = { title: 'KOI | Development avatar viewer' };
export default function Layout({ children }: { children: ReactNode }) {
  if (process.env.NODE_ENV !== 'development') notFound();
  return <html lang="en"><body>{children}</body></html>;
}
