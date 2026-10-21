'use client';
import { useEffect, useRef, useState } from 'react';
import NeoButton from '@/components/ui/NeoButton';
import NeoCard from '@/components/ui/NeoCard';
import { PlatformClientError, type ProfessionalApi } from '@/lib/platform/client';
import type { Connection, Page, Relationship } from '@/lib/platform/patient-types';
import type { Submission } from '@/lib/platform/professional-types';
import { completionEntries, countBy, last30Days, latestSubmissions, orderedSegments, segments, shortVersion, summaryTiles, type UsageSeries } from '@/lib/platform/analytics';
import { DailyBars, DonutChart } from './Charts';

const SEEN_LIMIT = 500;
const seenKey = (organizationId: string) => `koi.analytics.seen.${organizationId}`;
/** Per-browser convenience only; storage can be unavailable, so every access is guarded. */
export function readSeen(organizationId: string): Set<string> {
  try { const raw = window.localStorage.getItem(seenKey(organizationId)); const ids = raw ? JSON.parse(raw) : []; return new Set(Array.isArray(ids) ? ids.filter((id: unknown) => typeof id === 'string') : []); } catch { return new Set(); }
}
function writeSeen(organizationId: string, ids: Set<string>) {
  try { window.localStorage.setItem(seenKey(organizationId), JSON.stringify([...ids].slice(-SEEN_LIMIT))); } catch { /* unavailable storage: markers reset next visit */ }
}
interface Data { series: UsageSeries[] | null; submissions: Submission[] | null; relationships: Relationship[] | null; applications: Connection[] | null }
const relationshipLabels = { active: 'Active', closed: 'Closed / historical' };
const applicationLabels = { requested: 'Submitted', awaiting_demo_payment: 'Demo step required', pending_psychologist_review: 'Awaiting your review', accepted: 'Accepted', rejected: 'Declined', withdrawn: 'Withdrawn' };

export default function AnalyticsDashboard({ api, organizationId, onError, onView, compact = false }: { api: ProfessionalApi; organizationId: string; onError: (e: unknown) => void; onView: (submissionId: string) => void; compact?: boolean }) {
  const [data, setData] = useState<Data | null>(null), [busy, setBusy] = useState(false), [seen, setSeen] = useState<Set<string>>(() => new Set());
  const alive = useRef(true);
  const load = async () => {
    setBusy(true);
    const org = encodeURIComponent(organizationId);
    const [series, submissions, relationships, applications] = await Promise.allSettled([
      api.request<{ series: UsageSeries[] }>(`/api/v1/professional/analytics?organization_id=${org}`).then(r => r.series),
      api.request<Page<Submission>>(`/api/v1/professional/submissions?organization_id=${org}&`).then(r => r.items),
      api.request<Page<Relationship>>(`/api/v1/professional/patient-relationships?organization_id=${org}&`).then(r => r.items),
      api.request<Page<Connection>>('/api/v1/connection-requests?').then(r => r.items),
    ]);
    if (!alive.current) return;
    const failed = [series, submissions, relationships, applications].find(r => r.status === 'rejected') as PromiseRejectedResult | undefined;
    if (failed && failed.reason instanceof PlatformClientError && [401, 403].includes(failed.reason.status)) { onError(failed.reason); return; }
    const value = <T,>(r: PromiseSettledResult<T>) => r.status === 'fulfilled' && Array.isArray(r.value) ? r.value : null;
    setData({ series: value(series), submissions: value(submissions), relationships: value(relationships), applications: value(applications) });
    setBusy(false);
  };
  useEffect(() => { alive.current = true; setSeen(readSeen(organizationId)); void load().catch(e => { if (alive.current) { setBusy(false); onError(e); } }); return () => { alive.current = false; }; }, [api, organizationId]);
  const markSeen = (ids: string[]) => setSeen(old => { const next = new Set([...old, ...ids]); writeSeen(organizationId, next); return next; });

  if (!data) return <section className="care-analytics" aria-label="Practice summary" aria-busy="true">
    <div className="care-analytics-grid">{Array.from({ length: 6 }, (_, i) => <div key={i} className="care-tile care-skeleton" aria-hidden="true" />)}</div>
    <p role="status"><span className="neo-spinner" aria-hidden="true" />Loading practice summary…</p>
  </section>;
  const days = last30Days(data.series ?? []);
  const tiles = summaryTiles({ series: data.series ?? [], relationships: data.relationships ?? [], applications: data.applications ?? [], submissionsLoaded: data.submissions?.length ?? 0, days });
  const unavailable: Record<string, boolean> = { 'Active patients': !data.relationships, 'Assignments created': !data.series, 'Submitted attempts': !data.series, 'Submission rate': !data.series, 'Applications to review': !data.applications, 'Submissions, last 30 days': !data.series };
  const latest = latestSubmissions(data.submissions ?? []);
  const fresh = latest.filter(s => !seen.has(s.id));
  return <section className="care-analytics" aria-label="Practice summary" aria-busy={busy}>
    <ul className="care-analytics-grid" aria-label="Summary tiles">{tiles.map(t => <li key={t.label} className="care-tile"><span className="care-tile-label">{t.label}{t.derived && <span className="care-chip">Derived</span>}</span><strong className="care-tile-value">{unavailable[t.label] ? 'Unavailable' : t.value}</strong>{t.note && <span className="professional-muted">{t.note}</span>}</li>)}</ul>
    <NeoCard className="professional-card care-analytics-wide"><div className="professional-row professional-between"><h3>Latest submissions</h3>{fresh.length > 0 && <NeoButton variant="ghost" onClick={() => markSeen(fresh.map(s => s.id))}>Mark all as read</NeoButton>}</div>
      {!data.submissions ? <p>Submissions are unavailable right now.</p> : !latest.length ? <p className="care-chart-empty">No data yet</p> : <ul className="care-notification-list" aria-label="Latest submissions, newest first">{latest.map(s => <li key={s.id} className="care-notification" data-unread={!seen.has(s.id) || undefined}>
        {!seen.has(s.id) && <span className="care-new-badge">New</span>}
        <p><strong><bdi>{s.patient_uid}</bdi></strong> · {shortVersion(s.questionnaire_version_id)} · <time dateTime={s.submitted_at}>{new Date(s.submitted_at).toLocaleString()}</time></p>
        <div className="professional-row"><NeoButton onClick={() => { markSeen([s.id]); onView(s.id); }}>View submission</NeoButton>{!seen.has(s.id) && <NeoButton variant="ghost" onClick={() => markSeen([s.id])}>Mark as read</NeoButton>}</div>
      </li>)}</ul>}
      <p className="professional-muted">“New” is remembered in this browser only.</p>
    </NeoCard>
    {!compact && <>
      <div className="care-analytics-grid care-analytics-grid--charts">
        <DonutChart title="Assignment completion (derived)" unit="assignments" segments={orderedSegments(completionEntries(data.series ?? []))} />
        <DonutChart title="Submissions by questionnaire version" unit="submissions" segments={segments((data.series ?? []).map(s => ({ label: shortVersion(s.questionnaire_version_id), value: s.submitted })))} />
        <DonutChart title="Applications by state (loaded)" unit="applications" segments={segments(countBy(data.applications ?? [], a => a.state, applicationLabels))} />
        <DonutChart title="Patients by status (loaded roster)" unit="patients" segments={segments(countBy(data.relationships ?? [], r => r.state, relationshipLabels))} />
      </div>
      <NeoCard className="professional-card care-analytics-wide"><DailyBars title="Submissions per day, last 30 days (UTC)" days={days} /></NeoCard>
      <p className="professional-muted">Operational counts only. They do not measure symptoms, diagnoses or clinical improvement. “Loaded” charts use the first page of records.</p>
    </>}
    <NeoButton variant="ghost" disabled={busy} onClick={() => void load().catch(onError)}>Refresh summary</NeoButton>
  </section>;
}
