import React from 'react';
import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import type { CareNotification } from '@/lib/platform/community-types';
import type { CapabilitiesDTO } from '@/lib/platform/types';
import { unreadStore } from '@/lib/platform/messaging/unread-store';
import { platformLinks } from '@/lib/platform/navigation';
import { professionalViews } from '@/components/platform/WorkspaceFrame';
import { FeedbackProviders } from '@/components/ui/feedback';

const mockRequest = jest.fn();
let mockUser: { uid: string } | null = { uid: 'patient' };
jest.mock('@/lib/platform/professional-auth', () => ({ useProfessionalAuth: () => ({ loading: false, user: mockUser, currentUser: () => mockUser }) }));
jest.mock('@/lib/platform/client', () => ({ ...jest.requireActual('@/lib/platform/client'), professionalApi: () => ({ request: mockRequest, dispose: jest.fn() }) }));
import CareNotifications, { MAX_MARK_ALL, notificationDestination, sortNotifications } from '@/components/patient/CareNotifications';
import PlatformNavigation from '@/components/platform/PlatformNavigation';
import { PlatformClientError } from '@/lib/platform/client';

const notice = (id: string, kind: CareNotification['kind'], created_at: string, read = false): CareNotification => ({
  id, event_id: id, kind, created_at, ...(read ? { read_at: '2026-10-22T00:00:00Z' } : {}),
  reference: kind === 'new_message' ? { message_id: 'm-' + id } : kind === 'appointment_change' ? { appointment_id: 'a-' + id } : kind === 'assignment' ? { assignment_id: 's-' + id } : { connection_request_id: 'c-' + id },
});
let items: CareNotification[] = [];
const api = () => ({ dispose: jest.fn(), request: jest.fn(async (path: string, method?: string) => {
  if (method === 'POST') { const id = decodeURIComponent(path.split('/')[4]); const found = items.find(n => n.id === id)!; if (found.read_at) throw new PlatformClientError(409, 'conflict'); found.read_at = '2026-10-22T01:00:00Z'; return { ...found }; }
  return { items: items.map(n => ({ ...n })), next_cursor: null };
}) as any });
beforeEach(() => { unreadStore.reset(); items = [notice('old', 'assignment', '2026-10-01T00:00:00Z'), notice('newest', 'appointment_change', '2026-10-21T00:00:00Z'), notice('mid', 'application_state', '2026-10-10T00:00:00Z', true)]; });

it('sorts newest first and routes each kind to the matching screen per role', () => {
  expect(sortNotifications(items).map(n => n.id)).toEqual(['newest', 'mid', 'old']);
  expect(notificationDestination(items[1], 'patient').href).toBe('/patient?view=appointments');
  expect(notificationDestination(items[1], 'professional').href).toBe('/professional?view=appointments');
  expect(notificationDestination(items[0], 'patient').href).toBe('/patient?view=questionnaires#questionnaires');
  expect(notificationDestination(notice('m', 'new_message', 'x'), 'professional').href).toBe('/professional?view=messages#messages');
  expect(notificationDestination(items[2], 'professional').href).toBe('/professional?view=patients#patients');
});
it('marks New items, marks one as read and opening an item marks it read', async () => {
  const client = api(); render(<CareNotifications api={client} onError={jest.fn()} workspace="professional" />);
  const list = await screen.findByRole('list');
  const rows = within(list).getAllByRole('listitem');
  expect(rows[0]).toHaveTextContent('Appointment update'); expect(within(rows[0]).getByText('New')).toBeInTheDocument();
  expect(within(rows[1]).queryByText('New')).not.toBeInTheDocument();
  fireEvent.click(within(rows[2]).getByRole('button', { name: 'Mark as read' }));
  await waitFor(() => expect(within(screen.getAllByRole('listitem')[2]).queryByText('New')).not.toBeInTheDocument());
  const open = within(screen.getAllByRole('listitem')[0]).getByRole('link', { name: 'Open appointments' });
  expect(open).toHaveAttribute('href', '/professional?view=appointments');
  fireEvent.click(open);
  await waitFor(() => expect(client.request).toHaveBeenCalledWith('/api/v1/notifications/newest/read', 'POST', {}));
});
it('marks all unread sequentially, skipping already-read errors, with a generic snackbar', async () => {
  items = Array.from({ length: MAX_MARK_ALL + 5 }, (_, i) => notice('n' + i, 'appointment_change', `2026-10-${String(1 + (i % 28)).padStart(2, '0')}T00:00:00Z`));
  items[3].read_at = undefined; const client = api();
  render(<CareNotifications api={client} onError={jest.fn()} />, { wrapper: FeedbackProviders });
  await screen.findAllByText('New');
  // A notice read elsewhere meanwhile must not stop the loop.
  items[0].read_at = '2026-10-22T00:00:00Z';
  fireEvent.click(screen.getByRole('button', { name: 'Mark all as read' }));
  expect(await screen.findByText('Notifications marked as read')).toBeInTheDocument();
  const posts = (client.request as jest.Mock).mock.calls.filter(([, method]) => method === 'POST');
  expect(posts).toHaveLength(MAX_MARK_ALL);
});
it('shows an honest empty state', async () => {
  items = []; render(<CareNotifications api={api()} onError={jest.fn()} />);
  expect(await screen.findByText(/No notifications yet/)).toBeInTheDocument();
});

describe('navigation', () => {
  const caps = (professional: boolean, patient: boolean): CapabilitiesDTO => ({ uid: 'patient', contract_version: '0.5.0', account_state: 'registered', authorization_revision: 1, capabilities: { expert_directory: !professional, professional_workspace: professional, companion_account_sync: true, create_organization: false }, professional_organization_ids: professional ? ['org'] : [], active_patient_relationships: patient ? [{ relationship_id: 'rel', organization_id: 'org', psychologist_uid: 'pro' }] : [] });
  let polled: CareNotification[] = [];
  beforeEach(() => { polled = []; mockRequest.mockReset().mockImplementation((path: string) => path.startsWith('/api/v1/me/capabilities') ? Promise.resolve(caps(true, false)) : Promise.resolve({ items: polled, next_cursor: null })); });
  it('gives psychologists a Notifications view and menu item', () => {
    expect(professionalViews.some(v => v.id === 'notifications')).toBe(true);
    expect(platformLinks(caps(true, false)).find(l => l.label === 'Notifications')?.href).toBe('/professional?view=notifications#notifications');
  });
  it('badges the Notifications item and toasts a generic "New notification" after the first poll only', async () => {
    polled = [notice('a1', 'appointment_change', '2026-10-21T00:00:00Z')];
    render(<PlatformNavigation expanded />);
    expect(await screen.findByRole('link', { name: /Notifications\s+\(1 unread\)/ })).toBeInTheDocument();
    expect(screen.queryByText('New notification')).not.toBeInTheDocument();
    polled = [...polled, notice('a2', 'appointment_change', '2026-10-22T00:00:00Z')];
    await act(async () => { window.dispatchEvent(new Event('focus')); });
    expect(await screen.findByText('New notification')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Open notifications' })).toHaveAttribute('href', '/professional?view=notifications#notifications');
    expect(screen.queryByText(/a-a2|appointment_id/)).not.toBeInTheDocument();
    expect(screen.queryByText('New message')).not.toBeInTheDocument();
  });
});
