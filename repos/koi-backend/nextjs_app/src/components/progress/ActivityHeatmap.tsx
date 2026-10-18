'use client';
import { useState } from 'react';
import { heatmapWeeks, type HeatmapCell } from '@/lib/progress/dashboardModel';

/** Sequential single-hue ramp (reference blue); the lightest neutral means no saved activity that day. */
const STEPS = ['#ecebe7', '#9ec5f4', '#5598e7', '#256abf', '#104281'];
const LEGEND = ['0', '1', '2', '3', '4+'];
const step = (count: number) => Math.min(STEPS.length - 1, count);
const ROWS = ['Mon', '', 'Wed', '', 'Fri', '', 'Sun'];
const describe = (cell: HeatmapCell) => `${cell.day}: ${cell.count} saved ${cell.count === 1 ? 'activity' : 'activities'}`;

/** Calendar of saved activity records (check-ins, breathing, completed conversations) per Asia/Karachi day. */
export default function ActivityHeatmap({ days, weeks = 13, now = Date.now() }: { days: ReadonlyMap<string, number>; weeks?: number; now?: number }) {
  const [focus, setFocus] = useState<HeatmapCell | null>(null);
  const columns = heatmapWeeks(days, weeks, now);
  const total = [...days.values()].reduce((sum, count) => sum + count, 0);
  if (!total) return <p>No data yet.</p>;
  const size = 14, gap = 2, left = 26;
  return <figure className="my-3">
    <figcaption className="font-bold">Saved activity by day (last {weeks} weeks, Asia/Karachi)</figcaption>
    <svg role="img" aria-label={`Saved activity calendar for the last ${weeks} weeks. Days with activity are also listed below.`} viewBox={`0 0 ${left + columns.length * (size + gap)} ${7 * (size + gap)}`} className="w-full max-w-md" onMouseLeave={() => setFocus(null)}>
      {ROWS.map((label, row) => label && <text key={label} x={0} y={row * (size + gap) + 11} fontSize="9" fill="#52514e">{label}</text>)}
      {columns.map((column, w) => column.map((cell, d) => !cell.future && <rect key={cell.day} x={left + w * (size + gap)} y={d * (size + gap)} width={size} height={size} rx={3}
        fill={STEPS[step(cell.count)]} stroke={focus?.day === cell.day ? '#0b0b0b' : 'none'} strokeWidth={1.5} onMouseEnter={() => setFocus(cell)}><title>{describe(cell)}</title></rect>))}
    </svg>
    <p className="text-sm" aria-live="off">{focus ? describe(focus) : 'Hover a day to see its count.'}</p>
    <div className="flex items-center gap-1 text-xs mt-1" aria-label="Legend: saved activities per day">
      <span>Fewer</span>{STEPS.map((color, index) => <span key={color} className="inline-flex items-center gap-1"><svg width="12" height="12" aria-hidden="true"><rect width="12" height="12" rx="3" fill={color} /></svg>{LEGEND[index]}</span>)}<span>More</span>
    </div>
    <details className="mt-2"><summary className="cursor-pointer text-sm">Days with saved activity</summary>
      <ul className="flex flex-wrap gap-2 mt-2">{[...days.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([day, count]) => <li className="border-2 border-black rounded-lg p-1 text-sm" key={day}>{day}: {count}</li>)}</ul>
    </details>
  </figure>;
}
