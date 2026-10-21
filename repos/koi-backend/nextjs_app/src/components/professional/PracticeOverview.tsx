'use client';
import { useEffect, useRef, useState } from 'react';
import NeoCard from '@/components/ui/NeoCard';
import CareLink from '@/components/platform/CareLink';
import NeoButton from '@/components/ui/NeoButton';
import NeoInput from '@/components/ui/NeoInput';
import { PlatformClientError, type ProfessionalApi } from '@/lib/platform/client';
import type { VersionDTO } from '@/lib/platform/types';
interface Series { questionnaire_version_id: string; scoring_version: string; enrolled: number; submitted: number; points: Array<{ date: string; submitted: number }> }
function ActivitySeries({ series, api, from, to, onError }: { series: Series; api: ProfessionalApi; from: string; to: string; onError: (e: unknown) => void }) {
  const [snapshot, setSnapshot] = useState<VersionDTO | null>(null), [unavailable, setUnavailable] = useState(false);
  useEffect(() => {
    let current = true;
    api.request<VersionDTO>(`/api/v1/professional/questionnaire-versions/${encodeURIComponent(series.questionnaire_version_id)}`).then(value => { if (current) { if (value.content?.locales?.length) setSnapshot(value); else setUnavailable(true); } }).catch(e => { if (current) { setUnavailable(true); if (e instanceof PlatformClientError && [401, 403].includes(e.status)) onError(e); } });
    return () => { current = false; };
  }, [api, series.questionnaire_version_id]);
  const points = series.points.filter(p => (!from || p.date >= from) && (!to || p.date <= to));
  return <section className="professional-question"><h3>{snapshot ? snapshot.content.title[snapshot.content.locales[0]] : 'Published questionnaire'}{snapshot && ` · Revision ${snapshot.source_revision}`}</h3>
    {!snapshot && <p className="professional-muted">{unavailable ? 'Questionnaire title is unavailable. Activity counts are still shown below.' : 'Loading questionnaire title...'}</p>}
    <p>Assignments: {series.enrolled} · Submissions: {series.submitted}, all time · {points.reduce((n, p) => n + p.submitted, 0)} submitted in selected dates</p>
    <table><caption>Daily submitted attempts (UTC)</caption><thead><tr><th scope="col">Date</th><th scope="col">Submissions</th></tr></thead><tbody>{points.map(p => <tr key={p.date}><th scope="row">{p.date}</th><td><meter className="care-usage-meter" min={0} max={Math.max(...points.map(p => p.submitted), 1)} value={p.submitted} aria-label={`${p.date}: ${p.submitted} submissions`} /> {p.submitted}</td></tr>)}</tbody></table>
    {!points.length && <p>No submissions in this date range.</p>}
    <CareLink variant="secondary" href={`/professional?version=${encodeURIComponent(series.questionnaire_version_id)}`}>View published questionnaire</CareLink>
    <details><summary>Technical version details</summary><p>Published version: <code>{series.questionnaire_version_id}</code></p><p>Scoring applicability: <code>{series.scoring_version}</code></p></details>
  </section>;
}
export default function PracticeOverview({ api, organizationId, onError, view = 'profile' }: { view?: 'profile' | 'analytics'; api: ProfessionalApi; organizationId: string; onError: (e: unknown) => void }) {
  const [name, setName] = useState(''), [bio, setBio] = useState(''), [discoverable, setDiscoverable] = useState(false), [accepting, setAccepting] = useState(false), [revision, setRevision] = useState(0);
  const [series, setSeries] = useState<Series[]>([]), [from, setFrom] = useState(''), [to, setTo] = useState(''), [busy, setBusy] = useState(false), [error, setError] = useState(''), [message, setMessage] = useState('');
  const [visibleSeries, setVisibleSeries] = useState(10), [activityLoaded, setActivityLoaded] = useState(false);
  const alive = useRef(true), working = useRef(false);
  const run = async (fn: () => Promise<void>) => { if (working.current) return; working.current = true; setBusy(true); setError(''); try { await fn(); } catch (e) { if (alive.current) { setError('Unable to load or save practice information. Refresh before retrying a conflicting edit.'); onError(e); } } finally { working.current = false; if (alive.current) setBusy(false); } };
  const load = async () => {
    if (view === 'analytics') { const stats = await api.request<{ series: Series[] }>(`/api/v1/professional/analytics?organization_id=${encodeURIComponent(organizationId)}`); if (alive.current) { setSeries(stats.series); setActivityLoaded(true); } return; }
    try { const p = await api.request<any>(`/api/v1/professional/profile?organization_id=${encodeURIComponent(organizationId)}`); if (alive.current) { setName(p.display_name); setBio(p.bio); setDiscoverable(p.discoverable); setAccepting(p.accepting_new_patients); setRevision(p.revision); } } catch (e) { if (!(e instanceof PlatformClientError && e.status === 404)) throw e; }
    const stats = await api.request<{ series: Series[] }>(`/api/v1/professional/analytics?organization_id=${encodeURIComponent(organizationId)}`); if (alive.current) { setSeries(stats.series); setActivityLoaded(true); }
  };
  useEffect(() => { alive.current = true; void run(load); return () => { alive.current = false; }; }, [api, organizationId, view]);
  return <NeoCard className="professional-card"><h2 id={view === 'analytics' ? 'practice-analytics' : 'practice-dashboard'}>{view === 'analytics' ? 'Assignments & Submissions' : 'Public practice profile'}</h2>{busy && <p role="status"><span className="neo-spinner" aria-hidden="true" />Working…</p>}{error && <p role="alert">{error}</p>}<p role="status">{message}</p>
    {view === 'profile' && <div className="professional-stack"><div className="professional-grid care-overview-facts"><section><h3>{name || 'Practice profile not configured'}</h3><p>{discoverable ? 'Visible in Find an Expert' : 'Hidden from Find an Expert'}</p><p>{accepting ? 'Accepting new applications' : 'New applications paused'}</p></section><section><h3>Assignments &amp; Submissions</h3>{activityLoaded ? <><p>{series.reduce((total, item) => total + item.enrolled, 0)} assignments created</p><p>Submitted attempts: {series.reduce((total, item) => total + item.submitted, 0)}</p></> : <p>{busy ? 'Loading practice activity...' : 'Activity counts unavailable.'}</p>}<CareLink href="/professional?view=analytics#practice-analytics">Explore assignments and submissions</CareLink></section></div><details className="care-disclosure"><summary>Edit public practice profile</summary><div className="professional-stack care-profile-editor"><p className="professional-muted">This profile appears in Find an Expert when you enable visibility. Enable applications when you are ready to accept new patients.</p><form className="professional-stack care-readable-form" onSubmit={e => { e.preventDefault(); void run(async () => { const p = await api.request<any>('/api/v1/professional/profile', 'PUT', { organization_id: organizationId, display_name: name, bio, discoverable, accepting_new_patients: accepting, expected_revision: revision }); if (alive.current) { setRevision(p.revision); setMessage('Profile saved.'); } }); }}>
      <NeoInput aria-label="Public professional name" label="Public professional name" maxLength={160} required value={name} onChange={e => setName(e.target.value)} /><label>Professional biography<textarea className="neo-input" required maxLength={4000} value={bio} onChange={e => setBio(e.target.value)} /></label>
      <label><input type="checkbox" checked={discoverable} onChange={e => setDiscoverable(e.target.checked)} /> Show profile to registered General users and patients</label><label><input type="checkbox" checked={accepting} onChange={e => setAccepting(e.target.checked)} /> Accept new patient applications</label><NeoButton type="submit" disabled={busy}>Save public profile</NeoButton>
    </form></div></details></div>}{view === 'analytics' && <div className="professional-stack"><p>See how published questionnaires are used: how many assignments were created and how many attempts were submitted. Counts are grouped by published revision and UTC submission date. They do not measure symptoms, diagnoses or clinical improvement.</p>
    {activityLoaded && <div className="professional-grid care-usage-summary" aria-label="Assignment and submission totals"><div className="care-metric"><span>Assignments (all time)</span><strong>{series.reduce((total, item) => total + item.enrolled, 0)}</strong></div><div className="care-metric"><span>Submitted attempts (all time)</span><strong>{series.reduce((total, item) => total + item.submitted, 0)}</strong></div><div className="care-metric"><span>Submitted in selected dates</span><strong>{from && to && from > to ? 'Invalid date range' : series.reduce((total, item) => total + item.points.filter(point => (!from || point.date >= from) && (!to || point.date <= to)).reduce((sum, point) => sum + point.submitted, 0), 0)}</strong></div></div>}
    <div className="professional-row"><NeoInput aria-label="Activity from date" label="From (UTC date)" type="date" value={from} onChange={e => setFrom(e.target.value)} /><NeoInput aria-label="Activity to date" label="To (UTC date)" type="date" value={to} onChange={e => setTo(e.target.value)} /></div>{from && to && from > to && <p role="alert">Start date must precede end date.</p>}
    {activityLoaded && !series.length && <p>No questionnaire activity yet.</p>}{view === 'analytics' && series.slice(0, visibleSeries).map(item => <ActivitySeries key={item.questionnaire_version_id} series={item} api={api} from={from} to={to} onError={onError} />)}
    {series.length > visibleSeries && <NeoButton variant="ghost" onClick={() => setVisibleSeries(count => count + 10)}>Show more published versions</NeoButton>}

    </div>}<NeoButton variant="ghost" disabled={busy} onClick={() => void run(load)}>Refresh practice data</NeoButton>
  </NeoCard>;
}
