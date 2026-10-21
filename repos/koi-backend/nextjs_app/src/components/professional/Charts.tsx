'use client';
import { useId, useState, type KeyboardEvent } from 'react';
import { arcPath, segmentText, SURFACE, CATEGORICAL, type DayCount, type Segment } from '@/lib/platform/analytics';

/** Arrow keys move between marks; hover and focus show the same tooltip text that the table lists. */
function useActive(count: number) {
  const [active, setActive] = useState<number | null>(null);
  const keys = (event: KeyboardEvent) => {
    if (!count) return;
    if (event.key === 'ArrowRight' || event.key === 'ArrowDown') { event.preventDefault(); setActive(i => i === null ? 0 : (i + 1) % count); }
    if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') { event.preventDefault(); setActive(i => i === null ? count - 1 : (i - 1 + count) % count); }
    if (event.key === 'Escape') setActive(null);
  };
  return { active, setActive, keys };
}

export function DonutChart({ title, segments, unit = 'items' }: { title: string; segments: Segment[]; unit?: string }) {
  const id = useId(), { active, setActive, keys } = useActive(segments.length);
  const total = segments.reduce((n, s) => n + s.value, 0);
  let cursor = 0;
  const arcs = segments.map(s => { const from = cursor / total; cursor += s.value; return { s, d: arcPath(60, 60, 56, 34, from, cursor / total) }; });
  const summary = segments.length ? `${title}. ${segments.map(segmentText).join('; ')}.` : `${title}. No data yet.`;
  return <figure className="care-chart" aria-labelledby={`${id}-title`}>
    <figcaption id={`${id}-title`} className="care-chart-title">{title}</figcaption>
    {!segments.length ? <p className="care-chart-empty">No data yet</p> : <>
      <div className="care-donut-wrap">
        <svg viewBox="0 0 120 120" className="care-donut" role="img" aria-label={summary} tabIndex={0} onKeyDown={keys} onBlur={() => setActive(null)} onMouseLeave={() => setActive(null)}>
          {arcs.map(({ s, d }, i) => <path key={s.label} d={segments.length === 1 ? arcPath(60, 60, 56, 34, 0, 1) : d} fill={s.color} stroke={SURFACE} strokeWidth={2} opacity={active === null || active === i ? 1 : 0.45} onMouseEnter={() => setActive(i)} data-testid="donut-segment" />)}
          <text x="60" y="58" textAnchor="middle" className="care-donut-total">{total}</text>
          <text x="60" y="74" textAnchor="middle" className="care-donut-unit">{unit}</text>
        </svg>
        {active !== null && <div role="tooltip" className="care-chart-tooltip">{segmentText(segments[active])}</div>}
      </div>
      <ul className="care-chart-legend">{segments.map((s, i) => <li key={s.label} onMouseEnter={() => setActive(i)} onMouseLeave={() => setActive(null)}><span className="care-swatch" style={{ background: s.color }} aria-hidden="true" />{s.label}<span className="care-legend-value">{s.value}</span></li>)}</ul>
      <details><summary>Show as table</summary><table><caption>{title}</caption><thead><tr><th scope="col">Category</th><th scope="col">Count</th><th scope="col">Share</th></tr></thead><tbody>{segments.map(s => <tr key={s.label}><th scope="row">{s.label}</th><td>{s.value}</td><td>{s.percent}%</td></tr>)}</tbody></table></details>
    </>}
  </figure>;
}

export function DailyBars({ title, days }: { title: string; days: DayCount[] }) {
  const id = useId(), { active, setActive, keys } = useActive(days.length);
  const max = Math.max(...days.map(d => d.count), 0), total = days.reduce((n, d) => n + d.count, 0);
  const width = 300, height = 120, gap = 2, bar = (width - gap * (days.length - 1)) / Math.max(days.length, 1);
  const label = (d: DayCount) => `${d.date}: ${d.count} submission${d.count === 1 ? '' : 's'}`;
  return <figure className="care-chart care-chart--wide" aria-labelledby={`${id}-title`}>
    <figcaption id={`${id}-title`} className="care-chart-title">{title}</figcaption>
    {!total ? <p className="care-chart-empty">No data yet</p> : <>
      <div className="care-donut-wrap">
        <svg viewBox={`0 0 ${width} ${height + 16}`} className="care-bars" role="img" aria-label={`${title}. ${total} submissions in total; highest day ${max}. Use the arrow keys to read each day.`} tabIndex={0} onKeyDown={keys} onBlur={() => setActive(null)} onMouseLeave={() => setActive(null)}>
          <line x1="0" x2={width} y1={height} y2={height} stroke="#c9c8c3" strokeWidth="1" />
          {days.map((d, i) => { const h = max ? Math.max((d.count / max) * (height - 8), d.count ? 2 : 0) : 0, x = i * (bar + gap);
            return <g key={d.date} onMouseEnter={() => setActive(i)}>
              <rect x={x} y={0} width={bar} height={height} fill="transparent" />
              {h > 0 && <rect x={x} y={height - h} width={bar} height={h} rx={Math.min(4, bar / 2)} fill={CATEGORICAL[0]} opacity={active === null || active === i ? 1 : 0.5} data-testid="day-bar" />}
            </g>; })}
          <text x="0" y={height + 13} className="care-axis-label">{days[0]?.date}</text>
          <text x={width} y={height + 13} textAnchor="end" className="care-axis-label">{days[days.length - 1]?.date}</text>
        </svg>
        {active !== null && <div role="tooltip" className="care-chart-tooltip">{label(days[active])}</div>}
      </div>
      <details><summary>Show as table</summary><table><caption>{title}</caption><thead><tr><th scope="col">Date (UTC)</th><th scope="col">Submissions</th></tr></thead><tbody>{days.map(d => <tr key={d.date}><th scope="row">{d.date}</th><td>{d.count}</td></tr>)}</tbody></table></details>
    </>}
  </figure>;
}
