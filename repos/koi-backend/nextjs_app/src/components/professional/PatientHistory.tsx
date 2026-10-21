'use client';
import { useEffect, useRef, useState } from 'react';
import NeoCard from '@/components/ui/NeoCard';
import NeoButton from '@/components/ui/NeoButton';
import NeoInput from '@/components/ui/NeoInput';
import type { ProfessionalApi } from '@/lib/platform/client';
import { ACTION_FAILED, useConfirm, useSnackbar } from '@/components/ui/feedback';
import type { Relationship, Page } from '@/lib/platform/patient-types';
import type { Submission } from '@/lib/platform/professional-types';
export default function PatientHistory({ api, patient, onInspect, onError }: { api: ProfessionalApi; patient: Relationship; onInspect: (id: string) => void; onError: (e: unknown) => void }) {
  const [archive, setArchive] = useState({ archived: false, revision: 0 }), [items, setItems] = useState<Submission[]>([]), [cursor, setCursor] = useState<string | null>(null), [busy, setBusy] = useState(false), [error, setError] = useState(''), [from, setFrom] = useState(''), [to, setTo] = useState('');
  const alive = useRef(true);
  const base = `/api/v1/professional/patient-relationships/${patient.id}`;
  const load = async (next?: string) => { setBusy(true); try { const [a, p] = await Promise.all([api.request<typeof archive>(`${base}/archive`), api.request<Page<Submission>>(`${base}/submissions${next ? `?cursor=${encodeURIComponent(next)}` : ''}`)]); if (alive.current) { setArchive(a); setItems(old => next ? [...old, ...p.items] : p.items); setCursor(p.next_cursor); setError(''); } } catch (e) { if (alive.current) { setError('Unable to load patient history.'); onError(e); } } finally { if (alive.current) setBusy(false); } };
  useEffect(() => { alive.current = true; void load(); return () => { alive.current = false; }; }, [api, patient.id]);
  const confirm = useConfirm(), snackbar = useSnackbar();
  const toggle = async () => {
    const restoring = archive.archived;
    if (!(await confirm(restoring ? { title: 'Restore this historical record?', description: 'It returns to the practice roster. This does not reactivate care access.', confirmLabel: 'Restore record' } : { title: 'Archive this closed relationship?', description: 'Professional records remain retained.', confirmLabel: 'Archive relationship' }))) return;
    setBusy(true); try { const a = await api.request<typeof archive>(`${base}/archive`, 'POST', { expected_revision: archive.revision, archived: !archive.archived }); if (alive.current) { setArchive(a); snackbar.success(restoring ? 'Record restored' : 'Relationship archived'); } } catch (e) { if (alive.current) { setError('Unable to update archival state.'); snackbar.error(ACTION_FAILED); onError(e); } } finally { if (alive.current) setBusy(false); }
  };
  return <NeoCard className="professional-card"><h3>Patient details</h3><p>{patient.patient_uid} · {patient.state} · {archive.archived ? 'Archived' : 'In roster'}</p><p>Relationship activated {new Date(patient.activated_at).toLocaleString()}. Closing or archiving practice membership does not delete this person’s account.</p>{busy && <p role="status"><span className="neo-spinner" aria-hidden="true" />Loading…</p>}{error && <p role="alert">{error}</p>}{patient.state === 'closed' && <NeoButton disabled={busy} onClick={() => void toggle()}>{archive.archived ? 'Restore historical record' : 'Archive closed relationship'}</NeoButton>}
    <h4>Submitted questionnaire history</h4><div className="professional-row"><NeoInput aria-label="Patient history from date" label="From (UTC)" type="date" value={from} onChange={e => setFrom(e.target.value)} /><NeoInput aria-label="Patient history to date" label="To (UTC)" type="date" value={to} onChange={e => setTo(e.target.value)} /></div>{!items.length && <p>No submitted questionnaires.</p>}
    {items.filter(s => (!from || s.submitted_at.slice(0, 10) >= from) && (!to || s.submitted_at.slice(0, 10) <= to)).sort((a, b) => b.submitted_at.localeCompare(a.submitted_at)).map(s => <div className="professional-question" key={s.id}><p style={{ overflowWrap: 'anywhere' }}>{new Date(s.submitted_at).toLocaleString()} · {s.questionnaire_version_id}</p><NeoButton onClick={() => onInspect(s.id)}>Inspect patient submission</NeoButton></div>)}{cursor && <NeoButton disabled={busy} onClick={() => void load(cursor)}>More patient history</NeoButton>}
  </NeoCard>;
}
