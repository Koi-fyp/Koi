import React from 'react';
import { act, render, screen, waitFor } from '@testing-library/react';
import { platformLinks } from '@/lib/platform/navigation';
import { unreadStore } from '@/lib/platform/messaging/unread-store';
import type { CapabilitiesDTO } from '@/lib/platform/types';
import type { CareNotification } from '@/lib/platform/community-types';

const mockRequest = jest.fn(), mockDispose = jest.fn();
let mockUser: { uid: string } | null = { uid: 'patient' };
jest.mock('@/lib/platform/professional-auth', () => ({ useProfessionalAuth: () => ({ loading: false, user: mockUser, currentUser: () => mockUser }) }));
jest.mock('@/lib/platform/client', () => ({ professionalApi: () => ({ request: mockRequest, dispose: mockDispose }) }));
import PlatformNavigation from '@/components/platform/PlatformNavigation';

const caps = (professional: boolean, patient: boolean): CapabilitiesDTO => ({ uid: 'patient', contract_version: '0.5.0', account_state: 'registered', authorization_revision: 1, capabilities: { expert_directory: true, professional_workspace: professional, companion_account_sync: true, create_organization: false }, professional_organization_ids: professional ? ['org'] : [], active_patient_relationships: patient ? [{ relationship_id: 'rel', organization_id: 'org', psychologist_uid: 'pro' }] : [] });
const notice = (id: string, read = false): CareNotification => ({ id, event_id: id, kind: 'new_message', reference: { message_id: `message_${id}` }, created_at: '2026-01-01T00:00:00Z', ...(read ? { read_at: '2026-01-02T00:00:00Z' } : {}) });
let notices: CareNotification[] = [], capabilities = caps(false, true);
const route = (path: string) => { if (path.startsWith('/api/v1/me/capabilities')) return Promise.resolve(capabilities); if (path.startsWith('/api/v1/notifications')) return Promise.resolve({ items: notices, next_cursor: null }); return Promise.reject(new Error(path)); };
const poll = async () => { await act(async () => { window.dispatchEvent(new Event('focus')); }); };

beforeEach(() => { mockUser = { uid: 'patient' }; mockRequest.mockReset().mockImplementation(route); notices = []; capabilities = caps(false, true); unreadStore.reset(); document.title = 'KOI'; localStorage.clear(); });
afterEach(() => { delete (window as { Notification?: unknown }).Notification; jest.restoreAllMocks(); });

describe('Messages menu item', () => {
  it('appears for a patient with an active relationship, pointing at the messages screen', () => {
    const link = platformLinks(caps(false, true)).find(l => l.label === 'Messages');
    expect(link?.href).toBe('/patient?view=messages#messages');
    expect(platformLinks(caps(false, false)).map(l => l.label)).not.toContain('Messages');
  });
  it('appears for the professional workspace and keeps the existing items', () => {
    const labels = platformLinks(caps(true, false)).map(l => l.label);
    expect(platformLinks(caps(true, false)).find(l => l.label === 'Messages')?.href).toBe('/professional?view=messages#messages');
    expect(labels).toEqual(expect.arrayContaining(['Professional Dashboard', 'Professional Questionnaires', 'Patients', 'Submissions', 'Assignments & Submissions']));
    expect(labels).not.toContain('My Psychologist');
  });
});

describe('unread badge, title, toast and desktop notices', () => {
  it('shows the total as a badge (9+ cap) and puts it in the tab title, restoring it at zero', async () => {
    notices = [notice('1'), notice('2'), notice('3', true)];
    render(<PlatformNavigation expanded />);
    expect(await screen.findByText('2', { selector: '[aria-hidden="true"]' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /Messages\s+\(2 unread\)/ })).toBeInTheDocument();
    expect(document.title).toBe('(2) KOI');
    notices = Array.from({ length: 12 }, (_, i) => notice(`n${i}`)); await poll();
    expect(await screen.findByText('9+')).toBeInTheDocument(); expect(document.title).toBe('(12) KOI');
    notices = []; await poll();
    await waitFor(() => expect(document.title).toBe('KOI'));
    expect(screen.queryByText('9+')).not.toBeInTheDocument();
  });
  it('toasts "New message" (never the text) only for a notice that appears after the first load', async () => {
    notices = [notice('1')];
    render(<PlatformNavigation expanded />);
    await screen.findByRole('link', { name: /Messages/ }); await waitFor(() => expect(document.title).toBe('(1) KOI'));
    expect(screen.queryByText('New message')).not.toBeInTheDocument();
    notices = [notice('1'), notice('2')]; await poll();
    expect(await screen.findByText('New message')).toBeInTheDocument();
    expect(screen.queryByText(/message_2/)).not.toBeInTheDocument();
  });
  it('does not toast for a notice that belongs to the conversation that is open', async () => {
    notices = [notice('1')];
    render(<PlatformNavigation expanded />); await waitFor(() => expect(document.title).toBe('(1) KOI'));
    unreadStore.activeChat = { hasMessage: id => id === 'message_2', refresh: async () => undefined };
    notices = [notice('1'), notice('2')]; await poll(); await waitFor(() => expect(document.title).toBe('(2) KOI'));
    expect(screen.queryByText('New message')).not.toBeInTheDocument();
  });
  it('shows a desktop notification only when opted in, permitted, and the tab is in the background, with generic text', async () => {
    const created: Array<{ title: string; options?: NotificationOptions }> = [];
    class FakeNotification { static permission: NotificationPermission = 'granted'; static requestPermission = jest.fn(async () => 'granted' as NotificationPermission); constructor(title: string, options?: NotificationOptions) { created.push({ title, options }); } }
    (window as unknown as { Notification: unknown }).Notification = FakeNotification;
    localStorage.setItem('koi.messages.desktop', '1');
    const focus = jest.spyOn(document, 'hasFocus').mockReturnValue(true);
    notices = [notice('1')]; render(<PlatformNavigation expanded />); await waitFor(() => expect(document.title).toBe('(1) KOI'));
    notices = [notice('1'), notice('2')]; await poll(); await waitFor(() => expect(document.title).toBe('(2) KOI'));
    expect(created).toHaveLength(0); // focused tab: no desktop notice
    focus.mockReturnValue(false);
    notices = [notice('1'), notice('2'), notice('3')]; await poll(); await waitFor(() => expect(created).toHaveLength(1));
    expect(created[0].title).toBe('New message from your psychologist'); expect(JSON.stringify(created[0].options ?? {})).not.toMatch(/body/);
    expect(FakeNotification.requestPermission).not.toHaveBeenCalled();
  });
  it('never shows a desktop notification without the opt-in flag, even when permission is granted', async () => {
    const created: unknown[] = [];
    class FakeNotification { static permission: NotificationPermission = 'granted'; constructor() { created.push(1); } }
    (window as unknown as { Notification: unknown }).Notification = FakeNotification;
    jest.spyOn(document, 'hasFocus').mockReturnValue(false);
    notices = [notice('1')]; render(<PlatformNavigation expanded />); await waitFor(() => expect(document.title).toBe('(1) KOI'));
    notices = [notice('1'), notice('2')]; await poll(); await waitFor(() => expect(document.title).toBe('(2) KOI'));
    expect(created).toHaveLength(0);
  });
  it('stops polling and clears the badge when access is lost (403)', async () => {
    notices = [notice('1')]; render(<PlatformNavigation expanded />); await waitFor(() => expect(document.title).toBe('(1) KOI'));
    mockRequest.mockImplementation((path: string) => path.startsWith('/api/v1/notifications') ? Promise.reject({ status: 403 }) : route(path));
    await poll(); await waitFor(() => expect(document.title).toBe('KOI'));
    const calls = mockRequest.mock.calls.filter(c => String(c[0]).startsWith('/api/v1/notifications')).length;
    await poll(); expect(mockRequest.mock.calls.filter(c => String(c[0]).startsWith('/api/v1/notifications')).length).toBe(calls);
  });
  it('lets the store mark notices read sequentially and updates the badge', async () => {
    notices = [notice('1'), notice('2')]; render(<PlatformNavigation expanded />); await waitFor(() => expect(document.title).toBe('(2) KOI'));
    mockRequest.mockImplementation((path: string, method?: string) => method === 'POST' ? Promise.resolve({ ...notices.find(n => path.includes(n.id))!, read_at: 'now' }) : route(path));
    await act(async () => { await unreadStore.markRead?.(['1']); });
    await waitFor(() => expect(document.title).toBe('(1) KOI'));
    expect(mockRequest).toHaveBeenCalledWith('/api/v1/notifications/1/read', 'POST', {});
  });
});
