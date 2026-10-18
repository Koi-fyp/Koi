'use client';
import { useState } from 'react';
import type { SavedCheckIn } from '@/lib/checkins/checkInService';

/** Reference categorical slots 1-3 (validated; contrast is relieved by direct labels and the table). */
export const CHECK_IN_SERIES = [
  { key: 'mood', label: 'Mood', color: '#2a78d6', marker: 'circle' },
  { key: 'connection', label: 'Connection', color: '#eb6834', marker: 'square' },
  { key: 'energy', label: 'Energy', color: '#1baf7a', marker: 'triangle' },
] as const;
type SeriesKey = typeof CHECK_IN_SERIES[number]['key'];
const W = 320, H = 170, LEFT = 26, RIGHT = 78, TOP = 10, BOTTOM = 24;
const formatDay = (ms: number) => new Date(ms).toLocaleDateString('en-PK', { timeZone: 'Asia/Karachi', day: 'numeric', month: 'short' });
const formatTime = (iso: string) => new Date(iso).toLocaleString('en-PK', { timeZone: 'Asia/Karachi', dateStyle: 'medium', timeStyle: 'short' });

function Marker({ shape, x, y, color }: { shape: string; x: number; y: number; color: string }) {
  const ring = { stroke: '#fff', strokeWidth: 2, fill: color };
  if (shape === 'square') return <rect x={x - 4} y={y - 4} width={8} height={8} rx={1} {...ring} />;
  if (shape === 'triangle') return <polygon points={`${x},${y - 5} ${x + 5},${y + 4} ${x - 5},${y + 4}`} {...ring} />;
  return <circle cx={x} cy={y} r={4.5} {...ring} />;
}

/** Self-reported 1-5 ratings over a time window; values are shown as saved, never smoothed or scored. */
export default function CheckInChart({ entries, from, to, title = 'Check-in ratings' }: { entries: readonly SavedCheckIn[]; from: number | null; to: number; title?: string }) {
  const [hidden, setHidden] = useState<Set<SeriesKey>>(new Set());
  const [hover, setHover] = useState<number | null>(null);
  if (!entries.length) return <p>No data yet.</p>;
  const times = entries.map(entry => Date.parse(entry.completedAt));
  const start = from ?? Math.min(...times), end = Math.max(to, start + 1);
  const x = (ms: number) => entries.length === 1 && from === null ? LEFT + (W - LEFT - RIGHT) / 2 : LEFT + ((ms - start) / (end - start)) * (W - LEFT - RIGHT);
  const y = (value: number) => TOP + (5 - value) * ((H - TOP - BOTTOM) / 4);
  const visible = CHECK_IN_SERIES.filter(series => !hidden.has(series.key));
  const last = entries[entries.length - 1];
  const hovered = hover === null ? null : entries[hover];
  return <figure className="my-3">
    <figcaption className="font-bold">{title}</figcaption>
    <fieldset className="flex flex-wrap gap-3 my-2 text-sm"><legend className="sr-only">Show series</legend>
      {CHECK_IN_SERIES.map(series => <label key={series.key} className="flex items-center gap-1">
        <input type="checkbox" checked={!hidden.has(series.key)} onChange={() => setHidden(previous => { const next = new Set(previous); if (next.has(series.key)) next.delete(series.key); else next.add(series.key); return next; })} />
        <svg width="14" height="14" aria-hidden="true"><Marker shape={series.marker} x={7} y={7} color={series.color} /></svg>{series.label}
      </label>)}
    </fieldset>
    <div className="relative w-full max-w-md">
      <svg role="img" aria-label={`${title}: ${entries.length} saved check-ins, scale 1 to 5. Exact values are in the table.`} viewBox={`0 0 ${W} ${H}`} className="w-full" onMouseLeave={() => setHover(null)}>
        {[1, 2, 3, 4, 5].map(value => <g key={value}>
          <line x1={LEFT} x2={W - RIGHT} y1={y(value)} y2={y(value)} stroke="#e4e4e0" strokeWidth={1} />
          <text x={LEFT - 6} y={y(value) + 3} textAnchor="end" fontSize="9" fill="#52514e">{value}</text>
        </g>)}
        <text x={LEFT} y={H - 6} fontSize="9" fill="#52514e">{formatDay(start)}</text>
        <text x={W - RIGHT} y={H - 6} fontSize="9" fill="#52514e" textAnchor="end">{formatDay(end)}</text>
        {hovered && <line x1={x(Date.parse(hovered.completedAt))} x2={x(Date.parse(hovered.completedAt))} y1={TOP} y2={H - BOTTOM} stroke="#8c8b86" strokeWidth={1} strokeDasharray="2 2" />}
        {visible.map(series => <g key={series.key}>
          {entries.length > 1 && <polyline fill="none" stroke={series.color} strokeWidth={2} strokeLinejoin="round" strokeLinecap="round"
            points={entries.map(entry => `${x(Date.parse(entry.completedAt))},${y(entry[series.key])}`).join(' ')} />}
          {entries.map(entry => <Marker key={entry.id} shape={series.marker} x={x(Date.parse(entry.completedAt))} y={y(entry[series.key])} color={series.color} />)}
        </g>)}
        {/* Direct labels at the latest saved value; text uses ink, the marker carries identity. */}
        {visible.map((series, index) => <g key={series.key}>
          <Marker shape={series.marker} x={W - RIGHT + 10} y={TOP + 12 + index * 16} color={series.color} />
          <text x={W - RIGHT + 18} y={TOP + 15 + index * 16} fontSize="9" fill="#0b0b0b">{series.label} {last[series.key]}</text>
        </g>)}
        {entries.map((entry, index) => { const cx = x(Date.parse(entry.completedAt)); return <rect key={entry.id} x={cx - 8} y={TOP} width={16} height={H - TOP - BOTTOM} fill="transparent" onMouseEnter={() => setHover(index)} />; })}
      </svg>
      {hovered && <div role="tooltip" className="absolute pointer-events-none bg-white border-2 border-black rounded-lg px-2 py-1 text-xs"
        style={{ left: `${Math.min(70, Math.max(0, (x(Date.parse(hovered.completedAt)) / W) * 100 - 15))}%`, top: 0 }}>
        <div className="font-bold">{formatTime(hovered.completedAt)}</div>
        {CHECK_IN_SERIES.map(series => <div key={series.key}>{series.label}: {hovered[series.key]}</div>)}
      </div>}
    </div>
    <p className="text-sm">Self-reported ratings, 1 (low) to 5 (high). Latest saved values are labelled; the table lists every value.</p>
    <details className="mt-2"><summary className="cursor-pointer text-sm">Table view</summary>
      <div className="overflow-x-auto"><table className="w-full text-sm" aria-label="Saved check-in ratings"><thead className="text-left"><tr><th>Saved time</th><th>Mood</th><th>Connection</th><th>Energy</th></tr></thead>
        <tbody>{entries.map(entry => <tr key={entry.id}><td>{formatTime(entry.completedAt)}</td><td>{entry.mood}</td><td>{entry.connection}</td><td>{entry.energy}</td></tr>)}</tbody></table></div>
    </details>
  </figure>;
}
