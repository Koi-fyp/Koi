import React from 'react';
import { act, cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import ProfessionalWorkspace from '@/components/professional/ProfessionalWorkspace';
import { emptyContent } from '@/lib/platform/content';
import { unreadStore } from '@/lib/platform/messaging/unread-store';
import { PlatformClientError, type ProfessionalApi } from '@/lib/platform/client';
import { TextEncoder } from 'node:util';
import { webcrypto } from 'node:crypto';
Object.defineProperty(globalThis, 'TextEncoder', { configurable: true, value: TextEncoder });
Object.defineProperty(globalThis.crypto, 'subtle', { configurable: true, value: webcrypto.subtle });
// Read-only component interactions: transport and polling scheduling are test doubles.
const mockStart = jest.fn(), mockStop = jest.fn();
const mockPollRuns: Array<() => Promise<void>> = [];
jest.mock('@/lib/platform/messaging/poller', () => ({ createPoller: ({ run }: { run: () => Promise<void> }) => { mockPollRuns.push(run); return { start: mockStart, stop: mockStop }; } }));
const now = '2026-10-21T12:00:00Z';
const patients = ['Alpha', 'Beta'].map((name, index) => ({ id: 'rel' + (index + 1), organization_id: 'org', psychologist_uid: 'pro', patient_uid: 'Patient ' + name, state: 'active', revision: 1, activated_at: now }));
const content = () => { const result = emptyContent(); result.title.en = 'Fixture wellbeing form'; result.questions[0].prompt.en = 'Fixture answer'; return result; };
const draft = () => ({ id: 'draft1', organization_id: 'org', psychologist_uid: 'pro', revision: 2, content: content(), created_at: now, updated_at: now });
const version = () => ({ id: 'version1', questionnaire_id: 'draft1', organization_id: 'org', psychologist_uid: 'pro', source_revision: 1, content: content(), published_at: now, schema_version: '0.5.0', content_sha256: 'fictional-hash' });
const submission = { id: 'submission1', patient_uid: 'Patient Alpha', organization_id: 'org', submitted_at: now, questionnaire_version_id: 'version1', answers: [] };
function fixtureApi(): ProfessionalApi & { request: jest.Mock } {
  return { dispose: jest.fn(), request: jest.fn(async (path: string, method = 'GET') => {
    if (method !== 'GET') {
      if (path === '/api/v1/professional/patient-invitations') return { invitation_id: 'fixture-invite', token: 'fixture-token-not-a-credential', expires_at: now };
      throw new Error('Unexpected mutation in a read-only fixture test');
    }
    if (path.includes('/capabilities')) return { uid: 'pro', account_state: 'registered', capabilities: { professional_workspace: true }, professional_organization_ids: ['org'], active_patient_relationships: [] };
    if (path.includes('/questionnaire-versions/')) return version();
    if (path.endsWith('/questionnaires/draft1')) return draft();
    if (path.includes('/questionnaires?')) return { items: [draft()], next_cursor: null };
    if (path.includes('/submissions/submission1/workspace')) return { submission, questionnaire: { content: content() }, evaluation: { id: 'evaluation1', interpretation: null, validated_scores: [], evidence: [] }, job: { state: 'queued' }, review_revision: 0 };
    if (path.includes('/review-decisions')) return { items: [], next_cursor: null };
    if (path.endsWith('/archive')) return { archived: false, revision: 0 };
    if (path.includes('/patient-relationships/rel1/submissions') || path.includes('/professional/submissions?')) return { items: [submission], next_cursor: null };
    if (path.includes('/professional/patient-relationships?')) return { items: patients, next_cursor: null };
    if (path.includes('/relationships/rel') && path.includes('/messages')) { const id = path.includes('rel2') ? 'rel2' : 'rel1'; return { items: [{ id: id + '-message', relationship_id: id, sender_uid: id === 'rel2' ? 'Patient Beta' : 'Patient Alpha', body: 'Fixture message for ' + id, created_at: now }], next_cursor: null }; }
    if (path.includes('/profile')) return { display_name: 'Fixture practice', bio: 'Fixture biography', discoverable: true, accepting_new_patients: false, revision: 1 };
    if (path.includes('/analytics')) return { series: [{ questionnaire_version_id: 'version1', scoring_version: 'not_applicable', enrolled: 2, submitted: 1, points: [{ date: '2026-10-21', submitted: 1 }] }] };
    return { items: [], next_cursor: null };
  }) } as any;
}
let scroll: jest.Mock, api: ReturnType<typeof fixtureApi>;
beforeEach(() => {
  scroll = jest.fn(); Object.defineProperty(HTMLElement.prototype, 'scrollIntoView', { configurable: true, value: scroll });
  window.history.replaceState(null, '', '/professional?view=patients');
  unreadStore.reset(); mockPollRuns.length = 0; mockStart.mockClear(); mockStop.mockClear(); api = fixtureApi();
});
afterEach(() => {
  expect(api.request.mock.calls.filter(([path, method]) => method === 'POST' && /messages|questionnaire-drafts|review-decisions|appointments/.test(path))).toEqual([]);
  cleanup(); jest.restoreAllMocks();
});
const mount = () => render(<ProfessionalWorkspace api={api} onSessionExpired={jest.fn()} />);
const nav = () => within(screen.getByRole('navigation', { name: 'Practice navigation' }));
async function row(name: string) { return within((await screen.findByText(name, { selector: 'strong' })).closest('article')!); }
async function focused(id: string) { await waitFor(() => expect(document.activeElement).toBe(document.getElementById(id))); expect(scroll).toHaveBeenCalledWith({ behavior: 'auto', block: 'start', inline: 'nearest' }); }
it('reveals the selected patient, loads their history and returns focus when closed', async () => {
  mount(); const alpha = await row('Patient Alpha'); const trigger = alpha.getByRole('button', { name: 'Patient details' });
  fireEvent.click(trigger); await screen.findByRole('heading', { name: 'Patient details: Patient Alpha' }); await focused('selected-patient');
  expect(trigger).toHaveAttribute('aria-expanded', 'true');
  expect(api.request).toHaveBeenCalledWith('/api/v1/professional/patient-relationships/rel1/archive');
  fireEvent.click(screen.getByRole('button', { name: 'Close patient details' })); await waitFor(() => expect(trigger).toHaveFocus());
  fireEvent.click((await row('Patient Beta')).getByRole('button', { name: 'Patient details' }));
  await screen.findByRole('heading', { name: 'Patient details: Patient Beta' }); await focused('selected-patient');
});
it('navigates roster conversation actions to the correct existing Messages thread and preserves its draft', async () => {
  mount(); fireEvent.click((await row('Patient Beta')).getByRole('link', { name: 'Open conversation' }));
  await screen.findByRole('region', { name: /Conversation with Patient/ });
  expect(window.location.search).toBe('?view=messages&relationship=rel2');
  expect(await within(screen.getByRole('log')).findByText('Fixture message for rel2')).toBeVisible();
  expect(within(screen.getByRole('log')).queryByText('Fixture message for rel1')).not.toBeInTheDocument(); await focused('selected-human-conversation');
  fireEvent.change(screen.getByRole('textbox', { name: 'Message' }), { target: { value: 'Unsent fixture draft' } });
  fireEvent.click(nav().getByRole('link', { name: 'Patients & assignments' }));
  expect(mockStop).toHaveBeenCalled();
  expect(screen.queryByRole('textbox', { name: 'Message' })).not.toBeInTheDocument();
  await act(async () => { window.history.back(); });
  await waitFor(() => expect(screen.getByRole('textbox', { name: 'Message' })).toHaveValue('Unsent fixture draft'));
  await focused('selected-human-conversation');
  await act(async () => { window.history.forward(); });
  await screen.findByRole('heading', { name: 'Patients and assignments' });
});
it('does not select an unrelated thread for an unavailable relationship deep link', async () => {
  window.history.replaceState(null, '', '/professional?view=messages&relationship=not-in-roster'); mount();
  await screen.findByText(/This conversation is not available/);
  expect(screen.queryByRole('log')).not.toBeInTheDocument();
});
it('reveals a patient history submission and preserves unsaved review text between workspaces', async () => {
  mount(); fireEvent.click((await row('Patient Alpha')).getByRole('button', { name: 'Patient details' }));
  fireEvent.click(await screen.findByRole('button', { name: 'Inspect patient submission' }));
  await screen.findByRole('heading', { name: 'Submission and clinician review' }); await focused('selected-submission');
  expect(screen.getByText('submission1', { selector: 'code' })).toBeInTheDocument();
  fireEvent.change(screen.getByRole('textbox', { name: 'Psychologist conclusion' }), { target: { value: 'Unsent professional review fixture' } });
  fireEvent.click(nav().getByRole('link', { name: 'Practice overview' }));
  expect(screen.queryByRole('textbox', { name: 'Psychologist conclusion' })).not.toBeInTheDocument();
  await act(async () => { window.history.back(); });
  expect(await screen.findByRole('textbox', { name: 'Psychologist conclusion' })).toHaveValue('Unsent professional review fixture');
});
it('reveals a submission from the main submission list', async () => {
  window.history.replaceState(null, '', '/professional?view=submissions'); mount();
  fireEvent.click(await screen.findByRole('button', { name: 'Inspect submission' }));
  await screen.findByRole('heading', { name: 'Submission and clinician review' }); await focused('selected-submission');
});
it('opens a saved draft and a published version without discarding the editor', async () => {
  window.history.replaceState(null, '', '/professional?view=questionnaires'); mount();
  fireEvent.click(await screen.findByRole('button', { name: 'Open draft: Fixture wellbeing form' })); await focused('questionnaire-editor');
  fireEvent.change(screen.getByRole('textbox', { name: /Title.*English/ }), { target: { value: 'Unsaved fixture title' } });
  fireEvent.click(screen.getByRole('button', { name: 'Inspect published revision' })); await focused('published-questionnaire-panel');
  expect(screen.getByRole('textbox', { name: /Title.*English/ })).toHaveValue('Unsaved fixture title');
  expect(screen.getByRole('button', { name: 'Publish saved revision' })).toBeDisabled();
});
it('reveals the intended appointment panel, including selection from a roster link', async () => {
  mount(); fireEvent.click((await row('Patient Beta')).getByRole('link', { name: 'Appointments' }));
  await screen.findByRole('heading', { name: 'Appointments: Patient Beta' }); await focused('patient-appointments');
  expect(api.request).toHaveBeenCalledWith('/api/v1/relationships/rel2/appointments');
  fireEvent.click(screen.getByRole('button', { name: 'Back to patient selection' }));
  fireEvent.click((await row('Patient Alpha')).getByRole('button', { name: 'Manage appointments' }));
  await screen.findByRole('heading', { name: 'Appointments: Patient Alpha' }); await focused('patient-appointments');
});
it('reveals the created invitation using a fixture response only', async () => {
  mount(); await row('Patient Alpha'); fireEvent.click(screen.getByText('Invitations', { selector: 'summary' }));
  fireEvent.click(screen.getByRole('button', { name: 'Create secure invitation' }));
  await screen.findByRole('heading', { name: 'Invitation ready to share' }); await focused('created-invitation');
  expect((screen.getByRole('textbox', { name: 'Single-use invitation link' }) as HTMLInputElement).value).toContain('#invite=fixture-token-not-a-credential');
});
it('dashboard shortcuts reveal activity titles and route published links in place with history', async () => {
  window.history.replaceState(null, '', '/professional'); mount();
  fireEvent.click(await screen.findByRole('link', { name: 'View assignments and submissions' }));
  await screen.findByRole('heading', { name: /Fixture wellbeing form.*Revision 1/ }); await focused('workspace-heading');
  fireEvent.click(screen.getByRole('link', { name: 'View published questionnaire' })); await focused('published-questionnaire-panel');
  expect(window.location.search).toBe('?version=version1');
  await act(async () => { window.history.back(); });
  await screen.findByRole('heading', { name: 'Assignments & Submissions', level: 1 });
  await focused('workspace-heading');
});

it('clears cached message panes and drafts when access is revoked', async () => {
  const original = api.request.getMockImplementation()!;
  let forbidden = false;
  api.request.mockImplementation(async (...args: any[]) => { if (forbidden && String(args[0]).includes('/messages')) throw new PlatformClientError(403, 'forbidden'); return original(...args); });
  mount(); fireEvent.click((await row('Patient Beta')).getByRole('link', { name: 'Open conversation' }));
  await within(await screen.findByRole('log')).findByText('Fixture message for rel2');
  fireEvent.change(screen.getByRole('textbox', { name: 'Message' }), { target: { value: 'Unsent confidential fixture' } });
  forbidden = true;
  await act(async () => { await expect(mockPollRuns[mockPollRuns.length - 1]()).rejects.toMatchObject({ status: 403 }); });
  await screen.findByRole('heading', { name: 'Practice access required' });
  expect(screen.queryByRole('textbox', { name: 'Message' })).not.toBeInTheDocument();
  expect(document.body.textContent).not.toContain('Unsent confidential fixture');
});
