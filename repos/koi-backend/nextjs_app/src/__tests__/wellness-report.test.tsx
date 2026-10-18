/** @jest-environment jsdom */
import React from 'react';
import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
let mockUid = 'report-owner';
let mockData: Record<string, unknown> = {};
const mockDecrypt = jest.fn();
jest.mock('dexie', () => jest.requireActual('../../node_modules/dexie/dist/dexie.js'));
jest.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: { uid: mockUid } }) }));
jest.mock('@/lib/firebase', () => ({ auth: { get currentUser() { return { uid: mockUid }; } } }));
jest.mock('@/hooks/useActivityData', () => ({ useActivityData: () => mockData }));
jest.mock('@/lib/history/ownedDecryptor', () => ({ withOwnedDecryptor: async (_uid: string, _signal: AbortSignal, read: (d: (c: string) => Promise<string>) => Promise<unknown>) => ({ status: 'ready', value: await read(mockDecrypt) }) }));
jest.mock('next/navigation', () => ({ useRouter: () => ({ push: jest.fn(), back: jest.fn() }) }));
import { db } from '@/lib/db';
import { buildWellnessReport, REPORT_DISCLAIMER } from '@/lib/report/wellnessReport';
import ReportPage from '@/app/(authenticated)/settings/report/page';

const NOW = Date.parse('2026-10-19T12:00:00.000Z');
const entry = (id: string, iso: string, mood: number, connection: number, energy: number) => ({ id, completedAt: iso, mood, connection, energy });
const event = (id: string, source: 'check_in' | 'breathing' | 'conversation', day: string, sourceId = id) => ({ id, completion_id: id, owner_uid: mockUid, source_type: source, source_id: sourceId, completed_at: `${day}T06:00:00.000Z`, day_key: day, policy_version: 'p', provenance: {}, payload: null });
const reward = (id: string, day: string, slot: number) => ({ id, owner_uid: mockUid, source_type: 'check_in', completion_id: id, day_key: day, slot_index: slot, policy_version: 'p', awarded_at: `${day}T06:00:00.000Z` });
const populated = () => ({ owner: mockUid, status: 'ready', unreadable: 0, locked: false,
  entries: [entry('c1', '2026-10-10T06:00:00.000Z', 2, 3, 4), entry('c2', '2026-10-18T06:00:00.000Z', 4, 5, 2), entry('old', '2026-06-01T06:00:00.000Z', 1, 1, 1)],
  ledger: { events: [event('c1', 'check_in', '2026-10-10'), event('c2', 'check_in', '2026-10-18'), event('b1', 'breathing', '2026-10-12'), event('v1', 'conversation', '2026-10-15', 'conv-a'), event('old', 'check_in', '2026-06-01')],
    rewards: [reward('old', '2026-06-01', 1), reward('c1', '2026-10-10', 2)], milestones: [] } });
beforeEach(async () => {
  jest.spyOn(Date, 'now').mockReturnValue(NOW); mockDecrypt.mockReset().mockImplementation(async (c: string) => c.replace('cipher:', ''));
  mockData = { owner: mockUid, status: 'ready', unreadable: 0, locked: false, entries: [], ledger: { events: [], rewards: [], milestones: [] } };
  await db.messages.clear();
});
afterEach(() => jest.restoreAllMocks());

it('builds an empty range with no invented values', () => {
  const report = buildWellnessReport({ from: '2026-10-01', to: '2026-10-19', entries: [], events: [], rewards: [], milestones: [], conversations: [] });
  expect(report).toMatchObject({ checkIns: [], ratings: null, activity: { checkIns: 0, breathingSessions: 0, completedConversations: 0 }, piecesEarned: 0, conversations: [] });
  expect(() => buildWellnessReport({ from: '2026-10-19', to: '2026-10-01', entries: [], events: [], rewards: [], milestones: [], conversations: [] })).toThrow();
});
it('summarizes only records inside the chosen Karachi day range', () => {
  const data = populated();
  const report = buildWellnessReport({ from: '2026-10-01', to: '2026-10-19', entries: data.entries, events: data.ledger.events as never, rewards: data.ledger.rewards as never, milestones: [],
    conversations: [{ conversationId: 'conv-a', dayKeys: new Set(['2026-10-15']) }, { conversationId: 'conv-old', dayKeys: new Set(['2026-05-01']) }] });
  expect(report.checkIns.map(e => e.id)).toEqual(['c1', 'c2']);
  expect(report.ratings).toEqual({ mood: { min: 2, max: 4, average: 3 }, connection: { min: 3, max: 5, average: 4 }, energy: { min: 2, max: 4, average: 3 } });
  expect(report).toMatchObject({ activity: { checkIns: 2, breathingSessions: 1, completedConversations: 1 }, piecesEarned: 1, conversations: ['conv-a'] });
});
it('the page shows the fixed disclaimer and "No data yet" for an empty range', async () => {
  render(<ReportPage />);
  expect(screen.getAllByText(REPORT_DISCLAIMER, { exact: false }).length).toBeGreaterThanOrEqual(1);
  expect(screen.getByRole('note')).toHaveTextContent(REPORT_DISCLAIMER);
  await screen.findByRole('article');
  expect(screen.getByText('No data yet.')).toBeInTheDocument();
  expect(screen.getByText('Pieces earned in this period').nextElementSibling).toHaveTextContent('0');
});
it('a populated range shows real counts and chart; titles appear only when ticked; print uses window.print', async () => {
  mockData = populated();
  await db.messages.bulkPut([
    { id: 'u1', conversationId: 'conv-a', sender: 'user', content: 'cipher:Synthetic first message', timestamp: new Date('2026-10-15T06:00:00Z'), emotion: 'neutral', synced: false, ownerUid: mockUid },
    { id: 'a1', conversationId: 'conv-a', sender: 'ai', content: 'cipher:Synthetic reply', timestamp: new Date('2026-10-15T06:01:00Z'), emotion: 'neutral', synced: false, ownerUid: mockUid },
    { id: 'f1', conversationId: 'conv-f', sender: 'user', content: 'cipher:Foreign', timestamp: new Date('2026-10-15T06:00:00Z'), emotion: 'neutral', synced: false, ownerUid: 'someone-else' },
  ]);
  const print = jest.fn(); Object.defineProperty(window, 'print', { configurable: true, value: print });
  render(<ReportPage />);
  await waitFor(() => expect(screen.getByText('Conversations with messages').nextElementSibling).toHaveTextContent('1'));
  expect(screen.getByText('2 saved check-ins (self-reported, 1 to 5).')).toBeInTheDocument();
  expect(within(screen.getByRole('table', { name: 'Check-in summary' })).getByText('Mood').closest('tr')).toHaveTextContent('Mood234');
  expect(screen.getByText('Breathing sessions').nextElementSibling).toHaveTextContent('1');
  expect(screen.getByText('Pieces earned in this period').nextElementSibling).toHaveTextContent('1');
  expect(document.body.textContent).not.toMatch(/Synthetic|crisis_score|risk_category|HIGH|CRITICAL/);
  expect(mockDecrypt).not.toHaveBeenCalled();
  fireEvent.click(screen.getByLabelText(/Include my message titles/));
  expect(await screen.findByText('Synthetic first message')).toBeInTheDocument();
  expect(mockDecrypt).toHaveBeenCalledTimes(1);
  fireEvent.click(screen.getByRole('button', { name: 'Print / Save as PDF' }));
  expect(print).toHaveBeenCalledTimes(1);
  await act(async () => { fireEvent.change(screen.getByLabelText('From (Asia/Karachi)'), { target: { value: '2026-10-16' } }); });
  expect(screen.getByText('1 saved check-in (self-reported, 1 to 5).')).toBeInTheDocument();
  expect(screen.getByText('Conversations with messages').nextElementSibling).toHaveTextContent('0');
});
it('locked check-in ratings are reported as locked, not as zero', async () => {
  mockData = { ...populated(), entries: [], locked: true };
  render(<ReportPage />); await screen.findByRole('article');
  expect(screen.getByText('Saved check-in ratings are locked on this device and are not included.')).toBeInTheDocument();
});
