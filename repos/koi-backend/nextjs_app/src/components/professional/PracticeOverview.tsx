'use client';
import { useEffect, useRef, useState } from 'react';
import NeoCard from '@/components/ui/NeoCard';
import NeoButton from '@/components/ui/NeoButton';
import NeoInput from '@/components/ui/NeoInput';
import { PlatformClientError, type ProfessionalApi } from '@/lib/platform/client';
interface Series { questionnaire_version_id: string; scoring_version: string; enrolled: number; submitted: number; points: Array<{ date: string; submitted: number }> }
export default function PracticeOverview({ api, organizationId, onError }: { api: ProfessionalApi; organizationId: string; onError: (e: unknown) => void }) {
  const [name, setName] = useState(''), [bio, setBio] = useState(''), [discoverable, setDiscoverable] = useState(false), [accepting, setAccepting] = useState(false), [revision, setRevision] = useState(0);
  const [series, setSeries] = useState<Series[]>([]), [from, setFrom] = useState(''), [to, setTo] = useState(''), [busy, setBusy] = useState(false), [error, setError] = useState(''), [message, setMessage] = useState('');
  const alive = useRef(true), working = useRef(false);
  const run = async (fn: () => Promise<void>) => { if (working.current) return; working.current = true; setBusy(true); setError(''); try { await fn(); } catch (e) { if (alive.current) { setError('Unable to load or save practice information. Refresh before retrying a conflicting edit.'); onError(e); } } finally { working.current = false; if (alive.current) setBusy(false); } };
  const load = async () => {
    const stats = await api.request<{ series: Series[] }>(`/api/v1/professional/analytics?organization_id=${encodeURIComponent(organizationId)}`); if (alive.current) setSeries(stats.series);
    try { const p = await api.request<any>(`/api/v1/professional/profile?organization_id=${encodeURIComponent(organizationId)}`); if (alive.current) { setName(p.display_name); setBio(p.bio); setDiscoverable(p.discoverable); setAccepting(p.accepting_new_patients); setRevision(p.revision); } } catch (e) { if (!(e instanceof PlatformClientError && e.status === 404)) throw e; }
  };
  useEffect(() => { alive.current = true; void run(load); return () => { alive.current = false; }; }, [api, organizationId]);
  return <NeoCard className="professional-card"><h3 id="practice-dashboard">Practice profile and activity</h3>{busy && <p role="status"><span className="neo-spinner" aria-hidden="true" />Working…</p>}{error && <p role="alert">{error}</p>}<p role="status">{message}</p>
    <form className="professional-stack" onSubmit={e => { e.preventDefault(); void run(async () => { const p = await api.request<any>('/api/v1/professional/profile', 'PUT', { organization_id: organizationId, display_name: name, bio, discoverable, accepting_new_patients: accepting, expected_revision: revision }); if (alive.current) { setRevision(p.revision); setMessage('Profile saved.'); } }); }}>
      <NeoInput aria-label="Public professional name" label="Public professional name" maxLength={160} required value={name} onChange={e => setName(e.target.value)} /><label>Professional biography<textarea className="neo-input" required maxLength={4000} value={bio} onChange={e => setBio(e.target.value)} /></label>
      <label><input type="checkbox" checked={discoverable} onChange={e => setDiscoverable(e.target.checked)} /> Show profile to registered General users and patients</label><label><input type="checkbox" checked={accepting} onChange={e => setAccepting(e.target.checked)} /> Accept new patient applications</label><NeoButton type="submit" disabled={busy}>Save public profile</NeoButton>
    </form><h4 id="practice-analytics">Questionnaire activity</h4><p>Actual assignments and submitted attempts, grouped by exact published version. Manually authored forms have no validated scoring version. These counts do not measure clinical improvement.</p>
    <div className="professional-row"><NeoInput aria-label="Activity from date" label="From (UTC date)" type="date" value={from} onChange={e => setFrom(e.target.value)} /><NeoInput aria-label="Activity to date" label="To (UTC date)" type="date" value={to} onChange={e => setTo(e.target.value)} /></div>{from && to && from > to && <p role="alert">Start date must precede end date.</p>}
    {!series.length && <p>No questionnaire activity yet.</p>}{series.map(s => { const points = s.points.filter(p => (!from || p.date >= from) && (!to || p.date <= to)); return <section className="professional-question" key={s.questionnaire_version_id}><h4 style={{ overflowWrap: 'anywhere' }}>{s.questionnaire_version_id}</h4><p>{s.enrolled} assignments · {s.submitted} submissions, all time · {points.reduce((n, p) => n + p.submitted, 0)} submissions in selected dates</p><table><caption>Daily submitted attempts (UTC)</caption><thead><tr><th scope="col">Date</th><th scope="col">Submissions</th></tr></thead><tbody>{points.map(p => <tr key={p.date}><th scope="row">{p.date}</th><td><meter min={0} max={Math.max(...points.map(p => p.submitted), 1)} value={p.submitted} aria-label={`${p.date}: ${p.submitted} submissions`} /> {p.submitted}</td></tr>)}</tbody></table>{!points.length && <p>No submissions in this date range.</p>}</section>; })}
    <NeoButton variant="ghost" disabled={busy} onClick={() => void run(load)}>Refresh practice data</NeoButton>
  </NeoCard>;
}
