/** Practice analytics shaping. Pure functions over server records; nothing here invents a number. */
export interface UsageSeries { questionnaire_version_id: string; scoring_version?: string; enrolled: number; submitted: number; points: Array<{ date: string; submitted: number }> }
export interface Tile { label: string; value: string; note?: string; derived?: boolean }
export interface Segment { label: string; value: number; color: string; percent: number }
export interface DayCount { date: string; count: number }

/** Fixed categorical order (validated reference palette, light surface); never cycled. */
export const CATEGORICAL = ['#2a78d6', '#eb6834', '#1baf7a', '#eda100', '#e87ba4', '#008300', '#6250d6', '#e34948'] as const;
export const OTHER_COLOR = '#8a8984';
export const SURFACE = '#fcfcfb';

const sum = (values: number[]) => values.reduce((total, n) => total + n, 0);
export function summaryTiles(input: { series: UsageSeries[]; relationships: Array<{ state: string }>; applications: Array<{ state: string }>; submissionsLoaded: number; days: DayCount[] }): Tile[] {
  const assignments = sum(input.series.map(s => s.enrolled)), submitted = sum(input.series.map(s => s.submitted));
  const recent = sum(input.days.map(d => d.count));
  return [
    { label: 'Active patients', value: String(input.relationships.filter(r => r.state === 'active').length), note: 'In the loaded roster' },
    { label: 'Assignments created', value: String(assignments), note: 'All time' },
    { label: 'Submitted attempts', value: String(submitted), note: 'All time' },
    { label: 'Submission rate', value: assignments ? `${Math.round(Math.min(submitted / assignments, 1) * 100)}%` : 'No data yet', note: 'Derived: submitted ÷ assigned, capped at 100%', derived: true },
    { label: 'Applications to review', value: String(input.applications.filter(a => a.state === 'pending_psychologist_review').length), note: 'Waiting for your decision' },
    { label: 'Submissions, last 30 days', value: String(recent), note: 'UTC dates' },
  ];
}
/** Largest first; past the palette size everything else folds into one "Other" slice. */
export function segments(entries: Array<{ label: string; value: number }>, max = CATEGORICAL.length): Segment[] {
  const positive = entries.filter(e => e.value > 0);
  const total = sum(positive.map(e => e.value));
  if (!total) return [];
  const sorted = [...positive].sort((a, b) => b.value - a.value);
  const kept = sorted.length > max ? sorted.slice(0, max - 1) : sorted;
  const rest = sorted.length > max ? sorted.slice(max - 1) : [];
  const rows = [...kept.map((e, i) => ({ ...e, color: CATEGORICAL[i] as string })), ...(rest.length ? [{ label: `Other (${rest.length})`, value: sum(rest.map(e => e.value)), color: OTHER_COLOR }] : [])];
  return rows.map(r => ({ ...r, percent: Math.round((r.value / total) * 1000) / 10 }));
}
/** Keeps the given order (for an inherent sequence such as completion), still in fixed palette order. */
export function orderedSegments(entries: Array<{ label: string; value: number }>): Segment[] {
  const total = sum(entries.map(e => Math.max(0, e.value)));
  if (!total) return [];
  return entries.map((e, i) => ({ label: e.label, value: Math.max(0, e.value), color: CATEGORICAL[i % CATEGORICAL.length], percent: Math.round((Math.max(0, e.value) / total) * 1000) / 10 })).filter(s => s.value > 0);
}
export const completionEntries = (series: UsageSeries[]) => {
  const assigned = sum(series.map(s => s.enrolled)), submitted = sum(series.map(s => s.submitted));
  return [{ label: 'Submitted', value: Math.min(submitted, assigned) }, { label: 'Not yet submitted', value: Math.max(assigned - submitted, 0) }];
};
export const countBy = <T,>(items: T[], key: (item: T) => string, labels: Record<string, string> = {}) => {
  const counts = new Map<string, number>();
  for (const item of items) counts.set(key(item), (counts.get(key(item)) ?? 0) + 1);
  return [...counts].map(([k, value]) => ({ label: labels[k] ?? k.replaceAll('_', ' '), value }));
};
const iso = (d: Date) => d.toISOString().slice(0, 10);
/** Exactly 30 UTC days ending today, zero-filled; points outside the window are ignored. */
export function last30Days(series: UsageSeries[], today = new Date()): DayCount[] {
  const end = Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate());
  const days = Array.from({ length: 30 }, (_, i) => iso(new Date(end - (29 - i) * 86400000)));
  const counts = new Map(days.map(d => [d, 0]));
  for (const s of series) for (const p of s.points) if (counts.has(p.date)) counts.set(p.date, counts.get(p.date)! + p.submitted);
  return days.map(date => ({ date, count: counts.get(date)! }));
}
export const latestSubmissions = <T extends { id: string; submitted_at: string }>(items: T[], n = 8) => [...items].sort((a, b) => b.submitted_at.localeCompare(a.submitted_at) || b.id.localeCompare(a.id)).slice(0, n);
export const shortVersion = (id: string) => `Version …${id.slice(-6)}`;
/** SVG donut slice between two fractions of the circle. */
export function arcPath(cx: number, cy: number, r: number, inner: number, from: number, to: number): string {
  if (to - from >= 0.9999) to = from + 0.9999;
  const point = (radius: number, f: number) => { const a = f * 2 * Math.PI - Math.PI / 2; return `${(cx + radius * Math.cos(a)).toFixed(3)} ${(cy + radius * Math.sin(a)).toFixed(3)}`; };
  const large = to - from > 0.5 ? 1 : 0;
  return `M ${point(r, from)} A ${r} ${r} 0 ${large} 1 ${point(r, to)} L ${point(inner, to)} A ${inner} ${inner} 0 ${large} 0 ${point(inner, from)} Z`;
}
export const segmentText = (s: Segment) => `${s.label}: ${s.value} (${s.percent}%)`;
