import React from 'react';
import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { PlatformClientError, type ProfessionalApi } from '@/lib/platform/client';
import type { CapabilitiesDTO } from '@/lib/platform/types';
import type { Connection } from '@/lib/platform/patient-types';
const mockApi = jest.fn();
let mockGeneration = 1;
const mockUser = { uid: 'fresh-general-fixture', getIdToken: async () => 'fixture-only' };
jest.mock('@/lib/platform/client', () => ({ ...jest.requireActual('@/lib/platform/client'), professionalApi: (...args: unknown[]) => mockApi(...args) }));
jest.mock('@/lib/platform/access-monitor', () => ({ useAccessMonitor: () => ({ ready: true, generation: mockGeneration }) }));
jest.mock('@/lib/platform/professional-auth', () => ({ useProfessionalAuth: () => ({ user: mockUser, currentUser: () => mockUser, loading: false, error: false, signOut: jest.fn() }) }));
jest.mock('@/components/professional/RecentAuthentication', () => ({ useRecentAuthentication: () => ({ beforeMutation: async () => {}, dialog: null }) }));
jest.mock('@/components/messaging/MessagesScreen', () => ({ __esModule: true, default: () => <div>Static human-message fixture</div> }));
import PatientWorkspace from '@/components/patient/PatientWorkspace';
import PatientApp from '@/components/patient/PatientApp';

const profile = { id: 'directory-psychologist', display_name: 'Dr Fictional Example', bio: 'Authoritative fixture practice profile. English and Urdu consultations.', accepting_new_patients: true };
function fixture() {
  const caps: CapabilitiesDTO = { uid: mockUser.uid, contract_version: '0.5.0', account_state: 'registered', authorization_revision: 1, capabilities: { expert_directory: true, professional_workspace: false, companion_account_sync: true, create_organization: false }, professional_organization_ids: [], active_patient_relationships: [] };
  const data = { caps, records: [] as Connection[], conflict: false, unavailable: false };
  const makeApi = (): ProfessionalApi => ({ dispose: jest.fn(), request: jest.fn(async (path, method, body: any) => {
    if (path.endsWith('/capabilities')) return { ...data.caps, active_patient_relationships: [...data.caps.active_patient_relationships] };
    if (path === '/api/v1/experts') return { items: [profile, { ...profile, id: 'not-accepting', display_name: 'Unavailable fixture', accepting_new_patients: false }], next_cursor: null };
    if (path === '/api/v1/experts/' + profile.id) { if (data.unavailable) throw new PlatformClientError(404, 'not_found'); return profile; }
    if (path === '/api/v1/connection-requests' && method === 'POST') {
      if (data.conflict) throw new PlatformClientError(409, 'conflict');
      expect(body).toEqual({ psychologist_uid: profile.id, consent_version: 'care-consent-v1' });
      const record: Connection = { id: 'fresh-application', organization_id: 'fixture-practice', applicant_uid: caps.uid, psychologist_uid: profile.id, state: 'requested', demo_payment_state: 'demo_pending', revision: 1, created_at: '2026-10-21T00:00:00Z', updated_at: '2026-10-21T00:00:00Z' };
      data.records = [record]; return record;
    }
    if (path === '/api/v1/connection-requests') return { items: data.records, next_cursor: null };
    if (path.endsWith('/transition') || path.endsWith('/demo-payment')) {
      expect(body.expected_revision).toBe(data.records[0].revision);
      data.records[0] = { ...data.records[0], revision: data.records[0].revision + 1, state: path.endsWith('/demo-payment') ? 'pending_psychologist_review' : 'awaiting_demo_payment', demo_payment_state: path.endsWith('/demo-payment') ? 'demo_completed' : 'demo_pending' };
      return data.records[0];
    }
    return { items: [], next_cursor: null };
  }) as ProfessionalApi['request'] });
  return { data, makeApi };
}
const nav = () => screen.getByRole('navigation', { name: 'Care navigation' });
const originalFetch = global.fetch;
beforeEach(() => { global.fetch = jest.fn(); mockGeneration = 1; mockApi.mockReset(); window.history.replaceState(null, '', '/patient?view=experts'); });
afterEach(() => { global.fetch = originalFetch; });
async function choose() {
  fireEvent.click((await screen.findAllByRole('button', { name: 'Choose for application' }))[0]);
  await screen.findByRole('heading', { level: 1, name: 'My Applications' });
  await waitFor(() => expect(screen.getByRole('checkbox', { name: /^I consent to joining this practice/ })).toBeEnabled());
  await waitFor(() => expect(screen.queryByText('Confirming the selected psychologist...')).not.toBeInTheDocument());
}
it('shows the six requested General User entries and an honest professional entry without granting access', async () => {
  const { makeApi } = fixture(); render(<PatientWorkspace api={makeApi()} onDenied={jest.fn()} />);
  await screen.findByText('General User Dashboard');
  expect(within(nav()).getAllByRole('link').map(link => link.textContent)).toEqual(['Care Home', 'Find a Psychologist', 'My Applications', 'Become a Psychologist', 'Notifications', 'Account & Access']);
  fireEvent.click(within(nav()).getByRole('link', { name: 'Become a Psychologist' }));
  expect(await screen.findByRole('heading', { name: 'Professional registration is not available yet' })).toBeVisible();
  expect(screen.getByRole('link', { name: 'Professional sign-in / access' })).toHaveAttribute('href', '/account?entry=psychologist');
  expect(screen.queryByRole('button', { name: /register|verify|create practice/i })).not.toBeInTheDocument();
  expect(screen.queryByRole('link', { name: 'Professional Dashboard' })).not.toBeInTheDocument();
});
it('hands the authoritative selected profile to a visible form, validates consent and submits only UID and consent version', async () => {
  const { makeApi } = fixture(); const api = makeApi(); render(<PatientWorkspace api={api} onDenied={jest.fn()} />);
  await choose();
  const form = screen.getByRole('form', { name: 'Practice application' });
  expect(screen.getByRole('heading', { name: profile.display_name })).toBeVisible();
  expect(within(document.getElementById('practice-application')!).getByText(profile.bio, { selector: 'p' })).toBeVisible();
  expect(screen.queryByRole('textbox', { name: /account ID/i })).not.toBeInTheDocument();
  expect(window.location.search).toContain('psychologist=' + profile.id);
  expect(screen.getByRole('button', { name: 'Send Application' })).toBeDisabled();
  fireEvent.submit(form); expect((api.request as jest.Mock).mock.calls.some(([, method]) => method === 'POST')).toBe(false);
  fireEvent.click(within(form).getByRole('checkbox'));
  expect(screen.getByRole('button', { name: 'Send Application' })).toBeEnabled();
  fireEvent.click(screen.getByRole('button', { name: 'Send Application' }));
  expect(await screen.findByRole('heading', { name: 'Application recorded' })).toBeVisible();
  expect(screen.getByText('General User Dashboard')).toBeVisible();
  expect(await screen.findByRole('button', { name: 'Continue application' })).toBeVisible();
});
it('preserves selection and consent through care navigation and restores the profile with fresh consent after refresh', async () => {
  const { makeApi } = fixture(); const api = makeApi(); const first = render(<PatientWorkspace api={api} onDenied={jest.fn()} />);
  await choose(); fireEvent.click(screen.getByRole('checkbox', { name: /^I consent to joining this practice/ }));
  fireEvent.click(within(nav()).getByRole('link', { name: 'Notifications' }));
  expect(window.location.search).toContain('psychologist=' + profile.id);
  fireEvent.click(within(nav()).getByRole('link', { name: 'My Applications' }));
  expect(await screen.findByRole('checkbox', { name: /^I consent to joining this practice/ })).toBeChecked();
  first.unmount(); render(<PatientWorkspace api={makeApi()} onDenied={jest.fn()} />);
  expect(await screen.findByRole('heading', { name: profile.display_name })).toBeVisible();
  expect(screen.getByRole('checkbox', { name: /^I consent to joining this practice/ })).not.toBeChecked();
  expect(screen.getByRole('button', { name: 'Send Application' })).toBeDisabled();
});
it('keeps the genuine lifecycle and promotes/demotes only through refreshed capabilities without another login', async () => {
  const { makeApi, data } = fixture(); mockApi.mockImplementation(makeApi);
  const view = render(<PatientApp />); await choose();
  fireEvent.click(screen.getByRole('checkbox', { name: /^I consent to joining this practice/ })); fireEvent.click(screen.getByRole('button', { name: 'Send Application' }));
  fireEvent.click(await screen.findByRole('button', { name: 'Continue application' }));
  fireEvent.click(await screen.findByRole('button', { name: 'Complete demo step' }));
  await screen.findAllByText('Waiting for practice review'); expect(screen.getByText('General User Dashboard')).toBeVisible();
  data.records[0] = { ...data.records[0], state: 'accepted' };
  mockGeneration++; view.rerender(<PatientApp />);
  await screen.findByText('General User Dashboard'); expect(screen.queryByText('Patient Dashboard')).not.toBeInTheDocument();
  data.caps.active_patient_relationships = [{ relationship_id: 'fresh-relationship', organization_id: 'fixture-practice', psychologist_uid: profile.id }];
  mockGeneration++; view.rerender(<PatientApp />); expect(await screen.findByText('Patient Dashboard')).toBeVisible();
  expect(screen.getByRole('heading', { level: 1, name: 'My Care / Overview' })).toBeVisible();
  data.caps.active_patient_relationships = [];
  mockGeneration++; view.rerender(<PatientApp />); expect(await screen.findByText('General User Dashboard')).toBeVisible();
  expect(screen.getByText(/Your previous care relationship has ended/)).toBeVisible(); expect(data.records[0].state).toBe('accepted');
});
it('explains a generic conflict without inventing a known closed relationship or creating a new application', async () => {
  const { makeApi, data } = fixture(); data.conflict = true; const api = makeApi(); render(<PatientWorkspace api={api} onDenied={jest.fn()} />);
  await choose(); fireEvent.click(screen.getByRole('checkbox', { name: /^I consent to joining this practice/ })); fireEvent.click(screen.getByRole('button', { name: 'Send Application' }));
  expect(await screen.findByRole('alert')).toHaveTextContent('An existing or previous care relationship, or another application conflict, may prevent reapplying');
  expect(screen.getByRole('alert')).toHaveTextContent('No new application was confirmed');
  expect(screen.queryByRole('heading', { name: 'Application recorded' })).not.toBeInTheDocument(); expect(data.records).toHaveLength(0);
  expect(screen.getByText('General User Dashboard')).toBeVisible();
});
it('blocks unavailable profiles on restore and disables directory selection when not accepting', async () => {
  const { makeApi, data } = fixture(); const api = makeApi(); const view = render(<PatientWorkspace api={api} onDenied={jest.fn()} />);
  const buttons = await screen.findAllByRole('button', { name: 'Choose for application' }); expect(buttons[1]).toBeDisabled();
  view.unmount(); data.unavailable = true;
  window.history.replaceState(null, '', '/patient?view=applications&psychologist=' + profile.id);
  render(<PatientWorkspace api={makeApi()} onDenied={jest.fn()} />);
  expect(await screen.findByRole('alert')).toHaveTextContent('profile could not be confirmed');
  expect(screen.getByRole('button', { name: 'Send Application' })).toBeDisabled();
});
it('supports history-driven selection without displaying an unverified UID as a profile name', async () => {
  const { makeApi } = fixture(); render(<PatientWorkspace api={makeApi()} onDenied={jest.fn()} />); await choose();
  act(() => { window.history.pushState(null, '', '/patient?view=applications&psychologist=unknown'); window.dispatchEvent(new PopStateEvent('popstate')); });
  expect(await screen.findByRole('alert')).toHaveTextContent('profile could not be confirmed');
  expect(screen.queryByRole('heading', { name: 'unknown' })).not.toBeInTheDocument(); expect(screen.getByRole('button', { name: 'Send Application' })).toBeDisabled();
});
