'use client';
import Link from 'next/link';
import BackButton from '../components/BackButton';
import CiphertextExport from '@/components/data-portability/CiphertextExport';

export default function ExportPage() {
  return <div style={{ padding: '1.5rem', maxWidth: '480px', margin: '0 auto', minHeight: '100vh' }}>
    <BackButton />
    <h1 style={{ fontWeight: 900, fontSize: '2rem', letterSpacing: '-0.03em', marginBottom: '0.5rem' }}>Export My Data</h1>
    <p className="text-sm text-gray-600 mb-6">Choose a data copy separately from a readable report. Neither is currently an encrypted, restorable backup.</p>
    <CiphertextExport />
    <section className="neo-card p-6 mb-6" aria-labelledby="wellness-report-title">
      <h2 id="wellness-report-title" className="font-bold text-xl">Wellness Report</h2>
      <p className="text-sm my-3">A printable summary for a date range you choose, built only from check-ins, activities and pieces saved on this device. It never includes crisis information, risk scores or message content unless you choose to include message titles. Self-reported and app-activity data only; not a clinical assessment.</p>
      <p className="text-sm mb-4">A printed or saved PDF can be read by anyone who has it. It does not restore encrypted conversations.</p>
      <Link href="/settings/report" className="neo-btn-primary w-full inline-block text-center" style={{whiteSpace:'normal'}}>Open Wellness Report</Link>
    </section>
    <section className="neo-card p-5 bg-[var(--neo-yellow)]" aria-labelledby="restorable-backup-title">
      <h2 id="restorable-backup-title" className="font-bold">Restorable backup unavailable</h2>
      <p className="text-sm mt-3">Restoration needs verified existing-key access, an authenticated backup format and an approved atomic restore path. Data exports do not supply those guarantees. Losing the original device key can make encrypted data unreadable even with the same account.</p>
    </section>
  </div>;
}
