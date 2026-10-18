'use client';
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
      <div className="my-4 p-4 rounded-xl border-2 border-gray-200 bg-gray-50" role="status">
        <p className="font-bold">No wellness report has been generated.</p>
        <p className="text-sm mt-2">Verified report data is not connected. Mood trends, loneliness scores, insights and crisis logs are not inferred from your conversations or filled with sample values.</p>
      </div>
      <p className="text-sm mb-4">A readable report would expose its included content to anyone who can open the file. It would not restore encrypted conversations.</p>
      <button type="button" className="neo-btn-primary w-full" style={{whiteSpace:'normal'}} disabled title="Verified report data is not connected">Generate Wellness Report (unavailable)</button>
    </section>
    <section className="neo-card p-5 bg-[var(--neo-yellow)]" aria-labelledby="restorable-backup-title">
      <h2 id="restorable-backup-title" className="font-bold">Restorable backup unavailable</h2>
      <p className="text-sm mt-3">Restoration needs verified existing-key access, an authenticated backup format and an approved atomic restore path. Data exports do not supply those guarantees. Losing the original device key can make encrypted data unreadable even with the same account.</p>
    </section>
  </div>;
}
