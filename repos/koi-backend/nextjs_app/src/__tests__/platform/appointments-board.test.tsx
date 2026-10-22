import React from 'react';
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import AppointmentsBoard from '@/components/patient/AppointmentsBoard';
import { FeedbackProviders } from '@/components/ui/feedback';
import { proposalIssues, sortAppointments } from '@/lib/platform/appointments';
import { unreadStore } from '@/lib/platform/messaging/unread-store';
import type { Appointment } from '@/lib/platform/community-types';
import type { ProfessionalApi } from '@/lib/platform/client';

const now = Date.parse('2026-10-22T10:00:00Z');
const local = (offsetMinutes: number) => { const d = new Date(Date.now() + offsetMinutes * 60000); const pad = (n: number) => String(n).padStart(2, '0'); return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`; };
const appointment = (id: string, relationship_id: string, state: Appointment['state'], updated_at: string): Appointment => ({ id, relationship_id, state, revision: 1, updated_at });
let data: Record<string, Appointment[]>; let request: jest.Mock; let api: ProfessionalApi;
beforeEach(() => {
  unreadStore.reset();
  data = { r1: [appointment('a-old', 'r1', 'confirmed', '2026-10-01T00:00:00Z')], r2: [appointment('a-new', 'r2', 'proposed', '2026-10-21T00:00:00Z'), appointment('a-mid', 'r2', 'requested', '2026-10-10T00:00:00Z')] };
  request = jest.fn(async (path: string, method?: string) => {
    if (method === 'POST') return { id: 'created', relationship_id: 'r1', state: 'requested', revision: 1, updated_at: '2026-10-22T00:00:00Z' };
    const rel = path.split('/')[4]; return { items: data[rel] ?? [], next_cursor: null };
  });
  api = { request: request as any, dispose: jest.fn() };
});
const relationships = [{ id: 'r1', label: 'Psychologist one' }, { id: 'r2', label: 'Psychologist two' }];

describe('proposal validation', () => {
  it('requires a future start, an end after the start and 10-240 minutes', () => {
    expect(proposalIssues('', '', now)).toEqual({ start: 'Enter a start time.', end: 'Enter an end time.' });
    expect(proposalIssues('2026-10-22T09:00:00Z', '2026-10-22T09:30:00Z', now).start).toMatch(/future/);
    expect(proposalIssues('2026-10-22T11:00:00Z', '2026-10-22T10:30:00Z', now).end).toMatch(/after the start/);
    expect(proposalIssues('2026-10-22T11:00:00Z', '2026-10-22T11:05:00Z', now).end).toMatch(/at least 10/);
    expect(proposalIssues('2026-10-22T11:00:00Z', '2026-10-22T15:01:00Z', now).end).toMatch(/at most 240/);
    expect(proposalIssues('2026-10-22T11:00:00Z', '2026-10-22T11:50:00Z', now)).toEqual({});
  });
  it('sorts the latest change first', () => {
    expect(sortAppointments([...data.r1, ...data.r2]).map(a => a.id)).toEqual(['a-new', 'a-mid', 'a-old']);
  });
});

it('shows every relationship, latest first with a Latest chip, status chips and a New badge for changes by the other party', async () => {
  unreadStore.publish('patient', [{ id: 'n1', event_id: 'e', kind: 'appointment_change', reference: { appointment_id: 'a-new' }, created_at: '2026-10-21T00:00:00Z' }]);
  render(<AppointmentsBoard api={api} relationships={relationships} onError={jest.fn()} />);
  const list = await screen.findByRole('list', { name: 'Appointments, latest change first' });
  await waitFor(() => expect(within(list).getAllByRole('listitem')).toHaveLength(3));
  const rows = within(list).getAllByRole('listitem');
  expect(rows[0]).toHaveTextContent('Time proposed'); expect(within(rows[0]).getByText('Latest')).toBeInTheDocument(); expect(within(rows[0]).getByText('New')).toBeInTheDocument();
  expect(within(rows[1]).queryByText('Latest')).not.toBeInTheDocument(); expect(within(rows[1]).queryByText('New')).not.toBeInTheDocument();
  expect(rows[2]).toHaveTextContent('Confirmed'); expect(rows[2]).toHaveTextContent('Psychologist one');
  expect(within(rows[0]).getByRole('button', { name: 'Accept proposed time' })).toBeInTheDocument();
});
it('requests with a themed confirmation and a success snackbar; cancelling the dialog sends nothing', async () => {
  render(<AppointmentsBoard api={api} relationships={relationships} onError={jest.fn()} />, { wrapper: FeedbackProviders });
  await screen.findAllByRole('listitem');
  fireEvent.change(screen.getByRole('combobox', { name: 'Psychologist for the request' }), { target: { value: 'r2' } });
  fireEvent.click(screen.getByRole('button', { name: 'Request appointment' }));
  fireEvent.click(within(await screen.findByRole('alertdialog')).getByRole('button', { name: 'Cancel' }));
  expect(request.mock.calls.some(([, method]) => method === 'POST')).toBe(false);
  fireEvent.click(screen.getByRole('button', { name: 'Request appointment' }));
  fireEvent.click(within(await screen.findByRole('alertdialog', { name: 'Request an appointment?' })).getByRole('button', { name: 'Request appointment' }));
  expect(await screen.findByText('Appointment requested')).toBeInTheDocument();
  expect(request).toHaveBeenCalledWith('/api/v1/appointments', 'POST', { relationship_id: 'r2' });
});
it('lets the psychologist propose on the request itself with inline validation', async () => {
  data = { r2: [appointment('a-mid', 'r2', 'requested', '2026-10-10T00:00:00Z')] };
  render(<AppointmentsBoard api={api} professional relationships={[{ id: 'r2', label: 'patient-two' }]} onError={jest.fn()} />, { wrapper: FeedbackProviders });
  const row = (await screen.findAllByRole('listitem'))[0];
  const propose = within(row).getByRole('button', { name: 'Propose time' }); expect(propose).toBeDisabled();
  expect(screen.queryByRole('button', { name: 'Request appointment' })).not.toBeInTheDocument();
  fireEvent.change(within(row).getByLabelText('Proposed start time'), { target: { value: local(-60) } });
  expect(within(row).getByText('The start time must be in the future.')).toBeInTheDocument();
  expect(within(row).getByLabelText('Proposed start time')).toHaveAttribute('aria-invalid', 'true');
  fireEvent.change(within(row).getByLabelText('Proposed start time'), { target: { value: local(120) } });
  fireEvent.change(within(row).getByLabelText('Proposed end time'), { target: { value: local(110) } });
  expect(within(row).getByText('The end time must be after the start time.')).toBeInTheDocument(); expect(propose).toBeDisabled();
  fireEvent.change(within(row).getByLabelText('Proposed end time'), { target: { value: local(170) } });
  expect(propose).toBeEnabled(); expect(row.querySelector('.professional-error')).toBeNull(); fireEvent.click(propose);
  fireEvent.click(within(await screen.findByRole('alertdialog', { name: 'Propose this time?' })).getByRole('button', { name: 'Propose time' }));
  await screen.findByText('Time proposed');
  const post = request.mock.calls.find(([path]) => path === '/api/v1/appointments/a-mid/transition')!;
  expect(post[2]).toEqual({ expected_revision: 1, to_state: 'proposed', starts_at: new Date(local(120)).toISOString(), ends_at: new Date(local(170)).toISOString() });
});
it('shows an honest empty state for each role', async () => {
  data = {};
  const view = render(<AppointmentsBoard api={api} relationships={[{ id: 'r9', label: 'x' }]} onError={jest.fn()} />);
  expect(await screen.findByText(/No appointments yet/)).toBeInTheDocument(); view.unmount();
  render(<AppointmentsBoard api={api} professional relationships={[{ id: 'r9', label: 'x' }]} onError={jest.fn()} />);
  expect(await screen.findByText(/No appointment requests yet/)).toBeInTheDocument();
});
