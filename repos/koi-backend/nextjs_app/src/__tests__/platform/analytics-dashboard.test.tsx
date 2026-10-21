import React from 'react';
import { fireEvent, render, screen, within } from '@testing-library/react';
import { CATEGORICAL, OTHER_COLOR, completionEntries, last30Days, latestSubmissions, orderedSegments, segments, summaryTiles, type UsageSeries } from '@/lib/platform/analytics';
import { DailyBars, DonutChart } from '@/components/professional/Charts';
import AnalyticsDashboard, { readSeen } from '@/components/professional/AnalyticsDashboard';
import type { ProfessionalApi } from '@/lib/platform/client';

const series: UsageSeries[] = [
  { questionnaire_version_id: 'version-aaaaaa', enrolled: 4, submitted: 3, points: [{ date: '2026-10-20', submitted: 2 }, { date: '2026-08-01', submitted: 1 }] },
  { questionnaire_version_id: 'version-bbbbbb', enrolled: 2, submitted: 1, points: [{ date: '2026-10-22', submitted: 1 }] },
];
const today = new Date('2026-10-22T15:00:00Z');

describe('data shaping', () => {
  it('computes six tiles from real records only and labels the derived rate', () => {
    const days = last30Days(series, today);
    const tiles = summaryTiles({ series, relationships: [{ state: 'active' }, { state: 'closed' }, { state: 'active' }], applications: [{ state: 'pending_psychologist_review' }, { state: 'accepted' }], submissionsLoaded: 4, days });
    expect(tiles.map(t => [t.label, t.value])).toEqual([['Active patients', '2'], ['Assignments created', '6'], ['Submitted attempts', '4'], ['Submission rate', '67%'], ['Applications to review', '1'], ['Submissions, last 30 days', '3']]);
    expect(tiles.find(t => t.label === 'Submission rate')).toMatchObject({ derived: true });
    expect(summaryTiles({ series: [], relationships: [], applications: [], submissionsLoaded: 0, days: [] })[3].value).toBe('No data yet');
  });
  it('builds exactly 30 zero-filled UTC days and ignores points outside the window', () => {
    const days = last30Days(series, today);
    expect(days).toHaveLength(30); expect(days[0].date).toBe('2026-09-23'); expect(days[29]).toEqual({ date: '2026-10-22', count: 1 });
    expect(days.find(d => d.date === '2026-10-20')!.count).toBe(2); expect(days.reduce((n, d) => n + d.count, 0)).toBe(3);
  });
  it('assigns fixed palette order, folds overflow into Other and never shows empty slices', () => {
    const many = Array.from({ length: 10 }, (_, i) => ({ label: 'q' + i, value: 10 - i }));
    const result = segments(many);
    expect(result).toHaveLength(8); expect(result.slice(0, 7).map(s => s.color)).toEqual(CATEGORICAL.slice(0, 7));
    expect(result[7]).toMatchObject({ label: 'Other (3)', value: 6, color: OTHER_COLOR });
    expect(segments([{ label: 'a', value: 0 }])).toEqual([]);
    expect(orderedSegments(completionEntries(series)).map(s => [s.label, s.value, s.percent])).toEqual([['Submitted', 4, 66.7], ['Not yet submitted', 2, 33.3]]);
  });
  it('orders latest submissions newest first', () => {
    expect(latestSubmissions([{ id: 'a', submitted_at: '2026-10-01T00:00:00Z' }, { id: 'b', submitted_at: '2026-10-21T00:00:00Z' }]).map(s => s.id)).toEqual(['b', 'a']);
  });
});

describe('chart accessibility', () => {
  it('gives the donut a text alternative, a legend, a table and hover/keyboard tooltips', () => {
    render(<DonutChart title="Patients by status" unit="patients" segments={segments([{ label: 'Active', value: 3 }, { label: 'Closed', value: 1 }])} />);
    const chart = screen.getByRole('img', { name: /Patients by status/ });
    expect(chart).toHaveAccessibleName('Patients by status. Active: 3 (75%); Closed: 1 (25%).');
    fireEvent.mouseEnter(screen.getAllByTestId('donut-segment')[1]); expect(screen.getByRole('tooltip')).toHaveTextContent('Closed: 1 (25%)');
    fireEvent.keyDown(chart, { key: 'ArrowRight' }); expect(screen.getByRole('tooltip')).toHaveTextContent('Active: 3 (75%)');
    fireEvent.keyDown(chart, { key: 'Escape' }); expect(screen.queryByRole('tooltip')).not.toBeInTheDocument();
    const table = screen.getByRole('table', { name: 'Patients by status' });
    expect(within(table).getAllByRole('row').map(r => r.textContent)).toEqual(['CategoryCountShare', 'Active375%', 'Closed125%']);
  });
  it('shows "No data yet" instead of an empty chart', () => {
    render(<><DonutChart title="Empty donut" segments={[]} /><DailyBars title="Empty bars" days={last30Days([], today)} /></>);
    expect(screen.getAllByText('No data yet')).toHaveLength(2); expect(screen.queryByRole('img')).not.toBeInTheDocument();
  });
  it('describes the 30-day bars and reads each day by hover or arrow keys', () => {
    render(<DailyBars title="Submissions per day" days={last30Days(series, today)} />);
    const chart = screen.getByRole('img', { name: /Submissions per day\. 3 submissions in total; highest day 2/ });
    fireEvent.keyDown(chart, { key: 'ArrowLeft' }); expect(screen.getByRole('tooltip')).toHaveTextContent('2026-10-22: 1 submission');
    expect(screen.getAllByTestId('day-bar')).toHaveLength(2);
    expect(within(screen.getByRole('table', { name: 'Submissions per day' })).getAllByRole('row')).toHaveLength(31);
  });
});

describe('dashboard', () => {
  const submissions = [
    { id: 'sub-old', organization_id: 'org', relationship_id: 'r', assignment_id: 'a', attempt_id: 't', patient_uid: 'patient-one', questionnaire_version_id: 'version-aaaaaa', answers: [], submitted_at: '2026-10-01T00:00:00Z' },
    { id: 'sub-new', organization_id: 'org', relationship_id: 'r', assignment_id: 'a', attempt_id: 't', patient_uid: 'patient-two', questionnaire_version_id: 'version-bbbbbb', answers: [], submitted_at: '2026-10-21T00:00:00Z' },
  ];
  const api = (): ProfessionalApi => ({ dispose: jest.fn(), request: jest.fn(async (path: string) => {
    if (path.includes('/analytics')) return { series };
    if (path.includes('/submissions')) return { items: submissions, next_cursor: null };
    if (path.includes('/patient-relationships')) return { items: [{ id: 'r', state: 'active' }], next_cursor: null };
    return { items: [{ id: 'c', state: 'pending_psychologist_review' }], next_cursor: null };
  }) as any });
  beforeEach(() => localStorage.clear());
  it('puts real tiles and latest submissions first, marks New per browser and opens the review', async () => {
    const onView = jest.fn();
    render(<AnalyticsDashboard api={api()} organizationId="org" onError={jest.fn()} onView={onView} />);
    const tiles = await screen.findByRole('list', { name: 'Summary tiles' });
    expect(within(tiles).getAllByRole('listitem')).toHaveLength(6);
    expect(within(tiles).getByText('Assignments created').closest('li')).toHaveTextContent('6');
    const latest = screen.getByRole('list', { name: 'Latest submissions, newest first' });
    const rows = within(latest).getAllByRole('listitem');
    expect(rows[0]).toHaveTextContent('patient-two'); expect(within(rows[0]).getByText('New')).toBeInTheDocument();
    expect(tiles.compareDocumentPosition(screen.getAllByRole('img')[0]) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    fireEvent.click(within(rows[1]).getByRole('button', { name: 'Mark as read' }));
    expect(within(rows[1]).queryByText('New')).not.toBeInTheDocument(); expect(readSeen('org').has('sub-old')).toBe(true);
    fireEvent.click(within(rows[0]).getByRole('button', { name: 'View submission' }));
    expect(onView).toHaveBeenCalledWith('sub-new'); expect(readSeen('org').has('sub-new')).toBe(true);
  });
  it('still works when browser storage throws', async () => {
    const spy = jest.spyOn(Storage.prototype, 'getItem').mockImplementation(() => { throw new Error('blocked'); });
    jest.spyOn(Storage.prototype, 'setItem').mockImplementation(() => { throw new Error('blocked'); });
    render(<AnalyticsDashboard compact api={api()} organizationId="org" onError={jest.fn()} onView={jest.fn()} />);
    const rows = await screen.findAllByRole('listitem');
    expect(screen.getAllByText('New')).toHaveLength(2);
    fireEvent.click(screen.getAllByRole('button', { name: 'Mark as read' })[0]);
    expect(screen.getAllByText('New')).toHaveLength(1); expect(rows.length).toBeGreaterThan(0);
    expect(screen.queryByRole('img')).not.toBeInTheDocument(); // compact: no charts
    spy.mockRestore(); jest.restoreAllMocks();
  });
});
