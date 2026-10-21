import React from 'react';
import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import type { ProfessionalApi } from '@/lib/platform/client';
import { PlatformClientError } from '@/lib/platform/client';
import type { CapabilitiesDTO } from '@/lib/platform/types';
import type { Connection, PatientDetail } from '@/lib/platform/patient-types';
import { careEntryDestination } from '@/lib/platform/care-entry';
import { applicationLabel } from '@/lib/platform/care-state';
const mockApi = jest.fn();
let mockGeneration = 1;
const mockUser = { uid: 'patient-fixture', getIdToken: async () => 'fixture-only' };
jest.mock('@/lib/platform/client', () => ({ ...jest.requireActual('@/lib/platform/client'), professionalApi: (...args: unknown[]) => mockApi(...args) }));
jest.mock('@/lib/platform/access-monitor', () => ({ useAccessMonitor: () => ({ ready: true, generation: mockGeneration }) }));
jest.mock('@/lib/platform/professional-auth', () => ({ useProfessionalAuth: () => ({ user: mockUser, currentUser: () => mockUser, loading: false, error: false, signOut: jest.fn() }) }));
jest.mock('@/components/professional/RecentAuthentication', () => ({ useRecentAuthentication: () => ({ beforeMutation: async () => {}, dialog: null }) }));
jest.mock('@/components/messaging/MessagesScreen', () => ({ __esModule: true, default: () => <div>Read-only message fixture</div> }));
import PatientWorkspace from '@/components/patient/PatientWorkspace';
import PatientApp from '@/components/patient/PatientApp';
import { FeedbackProviders } from '@/components/ui/feedback';

const relation = (id: string) => ({ relationship_id: id, organization_id: 'org-' + id, psychologist_uid: 'pro-' + id });
const capabilities = (...ids: string[]): CapabilitiesDTO => ({ uid: mockUser.uid, contract_version: '0.5.0', account_state: 'registered', authorization_revision: 1, capabilities: { expert_directory: true, professional_workspace: false, companion_account_sync: true, create_organization: false }, professional_organization_ids: [], active_patient_relationships: ids.map(relation) });
const application = (state: Connection['state']): Connection => ({ id: 'application-1', organization_id: 'org-a', applicant_uid: mockUser.uid, psychologist_uid: 'pro-a', state, demo_payment_state: state === 'requested' || state === 'awaiting_demo_payment' ? 'demo_pending' : 'demo_completed', revision: 1, created_at: '2026-10-21T00:00:00Z', updated_at: '2026-10-21T00:00:00Z' });
const detail: Extract<PatientDetail, { attempt: unknown }> = {
  assignment: { id: 'assignment-a', relationship_id: 'a', organization_id: 'org-a', questionnaire_version_id: 'version-a', attempt_id: 'attempt-a', title: { en: 'Care form' }, state: 'in_progress', created_at: '2026-10-21T00:00:00Z' },
  questionnaire: { version_id: 'version-a', schema_version: '0.5.0', title: { en: 'Care form' }, locales: ['en', 'ur'], questions: [{ id: 'q', type: 'short_text', prompt: { en: 'Your response', ur: 'Fixture Urdu question' }, max_length: 200, required: true }] },
  attempt: { id: 'attempt-a', assignment_id: 'assignment-a', patient_uid: mockUser.uid, version_id: 'version-a', status: 'in_progress', answers: [], revision: 1, server_updated_at: '2026-10-21T00:00:00Z' },
};
function fixture(initialCaps = capabilities(), state: Connection['state'] = 'pending_psychologist_review') {
  const data = { caps: initialCaps, application: application(state) };
  const api: ProfessionalApi = { dispose: jest.fn(), request: jest.fn(async (path: string, method?: string) => {
    if (path.endsWith('/capabilities')) return data.caps;
    if (path.endsWith('/connection-requests')) return { items: [data.application], next_cursor: null };
    if (path.endsWith('/demo-payment')) { data.application = { ...data.application, state: 'pending_psychologist_review', demo_payment_state: 'demo_completed' }; return data.application; }
    if (path.endsWith('/patient/assignments')) return { items: data.caps.active_patient_relationships.some(r => r.relationship_id === 'a') ? [detail.assignment] : [], next_cursor: null };
    if (path.endsWith('/assignments/assignment-a')) return detail;
    if (method === 'PATCH') return { revision: 2 };
    if (path.endsWith('/notifications')) return { items: [{ id: 'notice-a', event_id: 'event-a', kind: 'application_state', reference: { connection_request_id: 'application-1' }, created_at: '2026-10-21T00:00:00Z' }], next_cursor: null };
    return { items: [], next_cursor: null };
  }) as ProfessionalApi['request'] };
  return { data, api };
}
const navigation = () => screen.getByRole('navigation', { name: 'Care navigation' });
const originalFetch = global.fetch;
afterEach(() => { global.fetch = originalFetch; });
beforeEach(() => { global.fetch = jest.fn(); window.history.replaceState(null, '', '/patient'); mockGeneration = 1; mockApi.mockReset(); });

it.each(['requested', 'awaiting_demo_payment', 'pending_psychologist_review', 'accepted'] as const)('keeps %s applications in the General User dashboard without active care', async state => {
  const { api } = fixture(capabilities(), state); render(<PatientWorkspace api={api} onDenied={jest.fn()} />);
  await screen.findByText('General User Dashboard');
  expect(within(navigation()).getAllByRole('link').map(el => el.textContent)).toEqual(['Care Home', 'Find a Psychologist', 'My Applications', 'Become a Psychologist', 'Notifications', 'Account & Access']);
  expect(screen.queryByRole('link', { name: 'Questionnaires' })).not.toBeInTheDocument();
  expect((api.request as jest.Mock).mock.calls.some(([path]) => path.includes('/patient/assignments'))).toBe(false);
  if (state === 'accepted') expect(await screen.findByText(/No active care relationship is currently available/)).toBeVisible();
});
it('does not promote after the existing demo payment step completes', async () => {
  const { api } = fixture(capabilities(), 'awaiting_demo_payment'); render(<PatientWorkspace api={api} onDenied={jest.fn()} />, { wrapper: FeedbackProviders });
  fireEvent.click(await screen.findByRole('button', { name: 'Complete demo step' }));
  // The demo step now asks first in the themed dialog.
  fireEvent.click(within(await screen.findByRole('alertdialog', { name: 'Complete the demo payment step?' })).getByRole('button', { name: 'Complete demo step' }));
  await screen.findByText('Waiting for practice review');
  expect(screen.getByText('General User Dashboard')).toBeVisible(); expect(screen.queryByText('Patient Dashboard')).not.toBeInTheDocument();
});
it('promotes automatically through the existing authorization generation without a new login', async () => {
  const general = fixture(), patient = fixture(capabilities('a'), 'accepted');
  mockApi.mockReturnValueOnce(general.api).mockReturnValue(patient.api);
  const view = render(<PatientApp />); await screen.findByText('General User Dashboard');
  fireEvent.click(within(navigation()).getByRole('link', { name: 'My Applications' }));
  mockGeneration++; view.rerender(<PatientApp />);
  await screen.findByText('Patient Dashboard');
  expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('My Care / Overview');
  expect(screen.getByRole('heading', { name: 'Your care is active' })).toBeVisible();
  expect(screen.queryByRole('textbox', { name: 'Invitation code' })).not.toBeInTheDocument();
  expect(screen.queryByRole('heading', { name: 'Applications' })).not.toBeInTheDocument();
  expect(within(navigation()).getAllByRole('link').filter(el => !el.closest('details')).map(el => el.textContent)).toEqual(['My Care / Overview', 'My Psychologist', 'Questionnaires', 'Messages', 'Appointments', 'Notifications', 'Account & Access']);
  expect(screen.getByText('Additional care options').closest('details')).not.toHaveAttribute('open');
  expect(general.api.dispose).toHaveBeenCalledTimes(1);
  expect(window.location.search).toBe('?view=home');
});
it('removes revoked attempts and returns to General User while retaining accepted history', async () => {
  const { api, data } = fixture(capabilities('a'), 'accepted'); render(<PatientWorkspace api={api} onDenied={jest.fn()} />);
  await screen.findByText('Patient Dashboard');
  fireEvent.click(within(navigation()).getByRole('link', { name: 'Questionnaires' }));
  fireEvent.click(await screen.findByRole('button', { name: 'Resume questionnaire' }));
  fireEvent.change(await screen.findByRole('textbox', { name: 'Your response' }), { target: { value: 'PRIVATE LOCAL RESPONSE' } });
  data.caps = capabilities(); fireEvent.click(screen.getByRole('button', { name: 'Refresh your care' }));
  await screen.findByText('General User Dashboard');
  expect(screen.getByText(/Your previous care relationship has ended/)).toBeVisible();
  expect(screen.queryByRole('textbox', { name: 'Your response', hidden: true })).not.toBeInTheDocument();
  expect(document.body.innerHTML).not.toContain('PRIVATE LOCAL RESPONSE');
  expect(screen.getByText('Application accepted previously')).toBeVisible();
  expect(data.application.state).toBe('accepted');
  expect(screen.queryByText('Application declined')).not.toBeInTheDocument();
  act(() => { window.history.pushState(null, '', '/patient?view=questionnaires'); window.dispatchEvent(new PopStateEvent('popstate')); });
  expect(screen.queryByRole('button', { name: 'Resume questionnaire' })).not.toBeInTheDocument();
  expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Care Home');
});
it('retains an authorized questionnaire and unsaved text when a different relationship closes', async () => {
  window.history.replaceState(null, '', '/patient?view=questionnaires');
  const first = fixture(capabilities('a', 'b'), 'accepted'), remaining = fixture(capabilities('a'), 'accepted');
  mockApi.mockReturnValueOnce(first.api).mockReturnValue(remaining.api);
  const view = render(<PatientApp />);
  fireEvent.click(await screen.findByRole('button', { name: 'Resume questionnaire' }));
  fireEvent.change(await screen.findByRole('textbox', { name: 'Your response' }), { target: { value: 'Keep my unsaved response' } });
  fireEvent.change(screen.getByRole('combobox'), { target: { value: 'ur' } });
  mockGeneration++; view.rerender(<PatientApp />);
  expect(screen.queryByRole('textbox', { name: 'Fixture Urdu question' })).not.toBeInTheDocument();
  await waitFor(() => expect(screen.getByRole('textbox', { name: 'Fixture Urdu question' })).toHaveValue('Keep my unsaved response'));
  expect(screen.getByText('Patient Dashboard')).toBeVisible();
  expect(screen.queryByText(/Your previous care relationship has ended/)).not.toBeInTheDocument();
  expect(window.location.search).toBe('?view=questionnaires');
  expect(first.api.dispose).toHaveBeenCalledTimes(1);
});
it('discards an attempt for a removed relationship even if another care relationship remains', async () => {
  window.history.replaceState(null, '', '/patient?view=questionnaires');
  const { api, data } = fixture(capabilities('a', 'b')); render(<PatientWorkspace api={api} onDenied={jest.fn()} />);
  fireEvent.click(await screen.findByRole('button', { name: 'Resume questionnaire' }));
  await screen.findByRole('textbox', { name: 'Your response' });
  data.caps = capabilities('b'); fireEvent.click(screen.getByRole('button', { name: 'Refresh your care' }));
  await waitFor(() => expect(screen.queryByRole('textbox', { name: 'Your response', hidden: true })).not.toBeInTheDocument());
  expect(screen.getByText('Patient Dashboard')).toBeVisible();
  expect(await screen.findByText(/No questionnaires have been assigned/)).toBeVisible();
});
it('preserves application form entries through a capability refresh and in-place Back/Forward', async () => {
  const { api } = fixture(); render(<PatientWorkspace api={api} onDenied={jest.fn()} />);
  fireEvent.click(await screen.findByText('Have an invitation code?'));
  fireEvent.change(screen.getByRole('textbox', { name: 'Invitation code' }), { target: { value: 'unsent-invitation' } });
  fireEvent.click(within(navigation()).getByRole('link', { name: 'My Applications' }));
  fireEvent.click(screen.getByRole('button', { name: 'Refresh your care' }));
  await waitFor(() => expect(screen.getByRole('textbox', { name: 'Invitation code' })).toHaveValue('unsent-invitation'));
  for (const path of ['/patient?view=notifications#notifications', '/patient?view=applications#applications']) {
    act(() => { window.history.pushState(null, '', path); window.dispatchEvent(new PopStateEvent('popstate')); });
  }
  expect(screen.getByRole('textbox', { name: 'Invitation code' })).toHaveValue('unsent-invitation');
});
it('renders readable notifications without fabricating a historic application decision', async () => {
  window.history.replaceState(null, '', '/patient?view=notifications'); const { api } = fixture();
  render(<PatientWorkspace api={api} onDenied={jest.fn()} />);
  expect(await screen.findByText(/Application update/)).toBeVisible();
  expect(screen.getByRole('link', { name: 'View current applications' })).toHaveAttribute('href', '/patient?view=applications#applications');
  expect(screen.getByText('application_state')).toBeInTheDocument();
  expect(screen.queryByText('Application declined')).not.toBeInTheDocument();
});
it('preserves directory search and avoids reading a hidden directory on authorization refresh', async () => {
  window.history.replaceState(null, '', '/patient?view=experts');
  const first = fixture(), next = fixture();
  const view = render(<PatientWorkspace api={first.api} onDenied={jest.fn()} />);
  fireEvent.change(await screen.findByRole('textbox', { name: 'Search loaded expert profiles' }), { target: { value: 'Keep my search' } });
  fireEvent.click(within(navigation()).getByRole('link', { name: 'Care Home' }));
  view.rerender(<PatientWorkspace api={next.api} onDenied={jest.fn()} />);
  await screen.findByText('General User Dashboard');
  expect((next.api.request as jest.Mock).mock.calls.some(([path]) => path.startsWith('/api/v1/experts'))).toBe(false);
  fireEvent.click(within(navigation()).getByRole('link', { name: 'Find a Psychologist' }));
  expect(await screen.findByRole('textbox', { name: 'Search loaded expert profiles' })).toHaveValue('Keep my search');
});
it('does not authorize patient URL choices and keeps professional entry independent', () => {
  expect(careEntryDestination('patient', capabilities())).toBeNull();
  expect(careEntryDestination('general', capabilities('a'))).toBe('/patient');
  const multi = { ...capabilities('a'), capabilities: { ...capabilities().capabilities, professional_workspace: true } };
  expect(careEntryDestination('psychologist', multi)).toBe('/professional?view=dashboard#practice-dashboard');
  expect(careEntryDestination('patient', multi)).toBe('/patient');
  expect(applicationLabel(application('accepted'), capabilities('b'))).toBe('Application accepted previously');
  expect(applicationLabel(application('accepted'), capabilities('a'))).toContain('Your care is active');
});
it('preserves privacy boundaries and never requests clinical evaluations or professional records', async () => {
  const { api } = fixture(capabilities('a')); render(<PatientWorkspace api={api} onDenied={jest.fn()} />);
  await screen.findByText('Patient Dashboard');
  expect(document.body.textContent).not.toMatch(/AI evaluation|interpretation|validated score|review conclusion|job state/i);
  expect((api.request as jest.Mock).mock.calls.some(([path]) => /professional|evaluation|review-decisions/.test(path))).toBe(false);
});
it('ignores stale assignment responses after the last relationship ends', async () => {
  const { api, data } = fixture(capabilities('a'));
  let rejectOld!: (error: unknown) => void;
  const safe = fixture(capabilities('a')).api.request;
  (api.request as jest.Mock).mockImplementation((path, method) => path.endsWith('/assignments/assignment-a') ? new Promise((_resolve, reject) => { rejectOld = reject; }) : path.endsWith('/capabilities') ? Promise.resolve(data.caps) : safe(path, method));
  window.history.replaceState(null, '', '/patient?view=questionnaires'); const denied = jest.fn(); const view = render(<PatientWorkspace api={api} onDenied={denied} />);
  fireEvent.click(await screen.findByRole('button', { name: 'Resume questionnaire' }));
  data.caps = capabilities(); view.rerender(<PatientWorkspace api={fixture(capabilities()).api} onDenied={denied} />);
  await screen.findByText('General User Dashboard');
  await act(async () => rejectOld(new PlatformClientError(403, 'forbidden')));
  expect(denied).not.toHaveBeenCalled(); expect(screen.queryByRole('textbox', { name: 'Your response' })).not.toBeInTheDocument();
});
