import React from 'react';
import { render } from '@testing-library/react';
import CheckInChart from '@/components/progress/CheckInChart';
import ActivityHeatmap from '@/components/progress/ActivityHeatmap';

// KOI tokens: --neo-blue, --neo-coral, --neo-mint, --neo-gray and the blue ramp built on --neo-blue.
const THEME = ['#2d63eb', '#ff6b6b', '#2dd36f', '#f4f4f4', '#c7d6fa', '#86a6f3', '#16399a'];
const NOW = Date.parse('2026-10-19T09:00:00Z');
const fills = (container: HTMLElement) => [...container.querySelectorAll('svg [fill]:not(text)')]
  .map((el) => el.getAttribute('fill')!.toLowerCase())
  .filter((fill) => !['none', 'transparent', '#fff'].includes(fill));

it('draws check-in series in the KOI theme palette', () => {
  const entries = [
    { id: 'a', completedAt: '2026-10-17T09:00:00Z', mood: 2, connection: 3, energy: 4 },
    { id: 'b', completedAt: '2026-10-18T09:00:00Z', mood: 4, connection: 2, energy: 5 },
  ];
  const { container } = render(<CheckInChart entries={entries} from={NOW - 7 * 86400000} to={NOW} />);
  const used = fills(container);
  expect(used.length).toBeGreaterThan(0);
  expect(used.every((fill) => THEME.includes(fill))).toBe(true);
  expect([...container.querySelectorAll('polyline')].map((line) => line.getAttribute('stroke')!.toLowerCase())).toEqual(['#2d63eb', '#ff6b6b', '#2dd36f']);
});

it('colours activity calendar cells from the KOI theme palette', () => {
  const days = new Map([['2026-10-15', 1], ['2026-10-16', 2], ['2026-10-17', 3], ['2026-10-18', 6]]);
  const { container } = render(<ActivityHeatmap days={days} now={NOW} />);
  const used = fills(container);
  expect(used).toEqual(expect.arrayContaining(['#f4f4f4', '#c7d6fa', '#86a6f3', '#2d63eb', '#16399a']));
  expect(used.every((fill) => THEME.includes(fill))).toBe(true);
});
