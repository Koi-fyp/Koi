import React from 'react';
import { fireEvent, render, screen, within } from '@testing-library/react';
import { activityDayCounts, dashboardCounts, filterCheckIns, heatmapWeeks } from '@/lib/progress/dashboardModel';
import CheckInChart from '@/components/progress/CheckInChart';
import ActivityHeatmap from '@/components/progress/ActivityHeatmap';
let mockUid = 'dash-owner';
let mockData: Record<string, unknown> = {};
jest.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: { uid: mockUid } }) }));
jest.mock('@/lib/firebase', () => ({ auth: { get currentUser() { return { uid: mockUid }; } } }));
jest.mock('@/lib/checkins/checkInService', () => ({ checkInAvailable: async () => undefined, saveCheckIn: jest.fn() }));
jest.mock('@/hooks/useActivityData', () => ({ useActivityData: () => mockData }));
import Activities from '@/components/progress/ActivityAvailability';

const NOW = Date.parse('2026-10-19T12:00:00.000Z');
const entry = (id: string, iso: string, mood = 3, connection = 4, energy = 2) => ({ id, completedAt: iso, mood, connection, energy });
const event = (id: string, source: 'check_in' | 'breathing' | 'conversation', day: string, sourceId = id) => ({ id, completion_id: id, owner_uid: mockUid, source_type: source, source_id: sourceId, completed_at: `${day}T06:00:00.000Z`, day_key: day, policy_version: 'p', provenance: {}, payload: null });
beforeEach(() => { jest.spyOn(Date, 'now').mockReturnValue(NOW); mockData = { owner: mockUid, status: 'ready', ledger: { events: [], rewards: [], milestones: [] }, entries: [], unreadable: 0, locked: false }; });
afterEach(() => jest.restoreAllMocks());

it('filters check-ins by 7/30/90 days and all time without altering values', () => {
  const entries = [entry('a', '2026-05-01T00:00:00.000Z'), entry('b', '2026-08-01T00:00:00.000Z'), entry('c', '2026-10-01T00:00:00.000Z'), entry('d', '2026-10-18T00:00:00.000Z')];
  expect(filterCheckIns(entries, '7d', NOW).map(e => e.id)).toEqual(['d']);
  expect(filterCheckIns(entries, '30d', NOW).map(e => e.id)).toEqual(['c', 'd']);
  expect(filterCheckIns(entries, '90d', NOW).map(e => e.id)).toEqual(['b', 'c', 'd']);
  expect(filterCheckIns(entries, 'all', NOW)).toEqual(entries);
});
it('counts saved records by source and Karachi day, and lays out Monday-first weeks', () => {
  const events = [event('1', 'check_in', '2026-10-19'), event('2', 'check_in', '2026-10-19'), event('3', 'breathing', '2026-10-18'), event('4', 'conversation', '2026-10-17', 'conv-a'), event('5', 'conversation', '2026-10-18', 'conv-a')];
  const days = activityDayCounts(events);
  expect(Object.fromEntries(days)).toEqual({ '2026-10-19': 2, '2026-10-18': 2, '2026-10-17': 1 });
  expect(dashboardCounts({ completedExchanges: 9, conversations: 2, events, rewards: [1, 2], milestones: [] }))
    .toEqual({ completedExchanges: 9, conversations: 2, completedConversations: 1, checkIns: 2, breathingSessions: 1, pieces: 2, milestones: 0 });
  const weeks = heatmapWeeks(days, 2, NOW);
  expect(weeks).toHaveLength(2); expect(weeks[1][0].day).toBe('2026-10-19'); // 19 Oct 2026 is a Monday
  expect(weeks[1][0].count).toBe(2); expect(weeks[1][1].future).toBe(true); expect(weeks[0][6]).toMatchObject({ day: '2026-10-18', count: 2 });
});
it('empty chart and calendar say "No data yet"', () => {
  render(<><CheckInChart entries={[]} from={null} to={NOW} /><ActivityHeatmap days={new Map()} now={NOW} /></>);
  expect(screen.getAllByText('No data yet.')).toHaveLength(2);
});
it('renders three labelled series with a legend, direct labels, hover tooltip and a table', () => {
  const view = render(<CheckInChart entries={[entry('a', '2026-10-10T00:00:00.000Z', 1, 2, 3), entry('b', '2026-10-18T00:00:00.000Z', 5, 4, 2)]} from={null} to={NOW} />);
  for (const label of ['Mood', 'Connection', 'Energy']) expect(screen.getByRole('checkbox', { name: label })).toBeChecked();
  expect(view.container.querySelectorAll('polyline')).toHaveLength(3);
  expect(screen.getByText('Mood 5')).toBeInTheDocument(); expect(screen.getByText('Energy 2')).toBeInTheDocument();
  fireEvent.mouseEnter(view.container.querySelectorAll('rect[fill="transparent"]')[1]);
  expect(screen.getByRole('tooltip')).toHaveTextContent('Mood: 5');
  fireEvent.click(screen.getByRole('checkbox', { name: 'Energy' }));
  expect(view.container.querySelectorAll('polyline')).toHaveLength(2);
  expect(within(screen.getByRole('table')).getAllByRole('row')).toHaveLength(3);
});
it('Progress dashboard shows real counts, range filter and calendar; no streaks, no inferred mood', () => {
  mockData = { ...mockData, entries: [entry('a', '2026-10-18T00:00:00.000Z'), entry('b', '2026-06-01T00:00:00.000Z')],
    ledger: { events: [event('a', 'check_in', '2026-10-18'), event('b', 'breathing', '2026-10-19')], rewards: [{}, {}], milestones: [] } };
  render(<Activities totals={{ completedExchanges: 4, conversations: 1 }} />);
  const counts = (label: string) => screen.getByText(label, { selector: 'dt' }).nextElementSibling;
  expect(counts('Completed exchanges')).toHaveTextContent('4'); expect(counts('Check-ins')).toHaveTextContent('1');
  expect(counts('Breathing sessions')).toHaveTextContent('1'); expect(counts('Earned pieces')).toHaveTextContent('2 of 25');
  expect(screen.getByRole('button', { name: '30 days' })).toHaveAttribute('aria-pressed', 'true');
  expect(within(screen.getByRole('table')).getAllByRole('row')).toHaveLength(2);
  fireEvent.click(screen.getByRole('button', { name: 'All time' }));
  expect(within(screen.getByRole('table')).getAllByRole('row')).toHaveLength(3);
  expect(screen.getByText(/Saved activity by day/)).toBeInTheDocument();
  expect(document.body.textContent).not.toMatch(/streak|you (have )?improved|risk score|mood score/i);
});
it('without saved activity the dashboard shows "No data yet" rather than invented values', () => {
  render(<Activities totals={{ completedExchanges: 0, conversations: 0 }} />);
  expect(screen.getAllByText('No data yet.')).toHaveLength(2);
});
