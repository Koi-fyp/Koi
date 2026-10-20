'use client';
import { useEffect, useRef, useState } from 'react';
import NeoCard from '@/components/ui/NeoCard';
import NeoButton from '@/components/ui/NeoButton';
import type { ProfessionalApi } from '@/lib/platform/client';
import type { Page } from '@/lib/platform/patient-types';
interface Notice { id: string; event_id: string; submission_id: string; created_at: string }
export default function SubmissionNotifications({ api, organizationId, onInspect, onError }: { api: ProfessionalApi; organizationId: string; onInspect: (id: string) => void; onError: (e: unknown) => void }) {
  const [items, setItems] = useState<Notice[]>([]), [cursor, setCursor] = useState<string | null>(null), [busy, setBusy] = useState(false), [error, setError] = useState('');
  const alive = useRef(true);
  const load = async (next?: string) => { setBusy(true); try { const p = await api.request<Page<Notice>>(`/api/v1/professional/submission-notifications?organization_id=${encodeURIComponent(organizationId)}${next ? `&cursor=${encodeURIComponent(next)}` : ''}`); if (alive.current) { setItems(old => next ? [...old, ...p.items] : p.items); setCursor(p.next_cursor); setError(''); } } catch (e) { if (alive.current) { setError('Submission updates unavailable.'); onError(e); } } finally { if (alive.current) setBusy(false); } };
  useEffect(() => { alive.current = true; void load(); return () => { alive.current = false; }; }, [api, organizationId]);
  return <NeoCard className="professional-card"><h3>Submission updates</h3>{busy && <p role="status"><span className="neo-spinner" aria-hidden="true" />Loading…</p>}{error && <p role="alert">{error}</p>}{!items.length && !busy && <p>No submission updates.</p>}{items.map(n => <div className="professional-row" key={n.id}><span>Questionnaire received · {new Date(n.created_at).toLocaleString()}</span><NeoButton onClick={() => onInspect(n.submission_id)}>Open received submission</NeoButton></div>)}{cursor && <NeoButton disabled={busy} onClick={() => void load(cursor)}>More updates</NeoButton>}<NeoButton variant="ghost" disabled={busy} onClick={() => void load()}>Refresh submission updates</NeoButton></NeoCard>;
}
