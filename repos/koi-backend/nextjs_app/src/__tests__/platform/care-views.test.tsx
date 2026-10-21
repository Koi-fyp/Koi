import React from 'react';
import { act, fireEvent, render, screen, waitFor, cleanup } from '@testing-library/react';
import { writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import ProfessionalWorkspace from '@/components/professional/ProfessionalWorkspace';
import PatientWorkspace from '@/components/patient/PatientWorkspace';
import AccountApp from '@/components/platform/AccountApp';
jest.mock('@/lib/platform/professional-auth', () => ({ useProfessionalAuth: () => ({ loading: false, user: null, error: false, currentUser: () => null, signIn: jest.fn() }) }));
jest.mock('@/components/platform/PlatformNavigation', () => ({ __esModule: true, default: () => <nav>Static account navigation</nav> }));
import SubmissionReview from '@/components/professional/SubmissionReview';
import { professionalViews, patientViews, viewFromLocation } from '@/components/platform/WorkspaceFrame';
import { emptyContent } from '@/lib/platform/content';
import type { ProfessionalApi } from '@/lib/platform/client';
// Static human-message fixture: never mount polling, notification permissions or transport.
jest.mock('@/components/messaging/MessagesScreen', () => ({ __esModule: true, default: () => <div>Human message layout fixture</div> }));
const caps = (professional = false, patient = false) => ({ uid: 'fixture-account', account_state: 'registered', capabilities: { professional_workspace: professional, expert_directory: !professional }, professional_organization_ids: professional ? ['fixture-practice'] : [], active_patient_relationships: patient ? [{ relationship_id: 'fixture-relationship', organization_id: 'fixture-practice', psychologist_uid: 'fixture-psychologist' }] : [] });
function apiFor(professional = false, patient = false): ProfessionalApi {
  return { dispose: jest.fn(), request: jest.fn(async (path: string) => {
    if (path.includes('capabilities')) return caps(professional, patient);
    if (path.includes('/profile')) return { display_name: 'Fictional care practice', bio: 'A static test practice', revision: 1, discoverable: false, accepting_new_patients: false };
    if (path.includes('/analytics')) return { series: [{ questionnaire_version_id: 'fictional-published-version-for-layout-only', scoring_version: 'not_applicable', enrolled: 3, submitted: 1, points: [{ date: '2026-10-21', submitted: 1 }] }] };
    if (path.includes('/patient-relationships')) return { items: [{ id: 'fixture-relationship', revision: 1, state: 'active', patient_uid: 'fictional-patient-account-with-a-long-identifier-for-responsive-layout-checking' }], next_cursor: null };
    if (path.includes('/patient/assignments')) return { items: [{ id: 'fixture-assignment', relationship_id: 'fixture-relationship', state: 'assigned', title: { en: 'A fictional questionnaire with a longer title for responsive layout checks' } }], next_cursor: null };
    if (path.includes('/connection-requests')) return { items: [{ id: 'fixture-application', revision: 1, state: 'pending_psychologist_review', psychologist_uid: 'fictional-psychologist', applicant_uid: 'fixture-account' }], next_cursor: null };
    return { items: [], next_cursor: null };
  }) as any };
}
async function preview(name: string) {
  await act(async () => { await Promise.resolve(); });
  const directory = process.env.KOI_CARE_PREVIEW_DIR;
  if (directory) {
    const body = document.body.cloneNode(true) as HTMLElement;
    // Serialize current DOM form properties: innerHTML alone loses select and textarea values.
    const controls = document.body.querySelectorAll('input,textarea,select');
    body.querySelectorAll('input,textarea,select').forEach((copy, index) => {
      const current = controls[index] as HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement;
      if (copy instanceof HTMLInputElement) { copy.setAttribute('value', current.value); copy.toggleAttribute('checked', (current as HTMLInputElement).checked); }
      if (copy instanceof HTMLTextAreaElement) copy.textContent = current.value;
      if (copy instanceof HTMLSelectElement) [...copy.options].forEach(option => option.toggleAttribute('selected', option.value === current.value));
    });
    mkdirSync(directory, { recursive: true }); writeFileSync(join(directory, name + '.html'), body.innerHTML);
  }
}

beforeEach(() => { window.history.replaceState(null, '', '/professional'); });
afterEach(() => { cleanup(); jest.restoreAllMocks(); });
it('opens practice overview, changes views in place and preserves authoring edits through history', async () => {
  const api = apiFor(true); render(<ProfessionalWorkspace api={api} onSessionExpired={jest.fn()} />);
  await screen.findByRole('heading', { name: 'Public practice profile' });
  fireEvent.click(screen.getByText('Edit public practice profile'));
  await waitFor(() => expect(screen.getByRole('textbox', { name: 'Public professional name' })).toHaveValue('Fictional care practice'));
  expect(screen.queryByRole('heading', { name: 'Your questionnaires' })).not.toBeInTheDocument();
  await preview('professional-dashboard');
  fireEvent.click(screen.getByRole('link', { name: 'Questionnaires' }));
  expect(await screen.findByRole('heading', { name: 'Your questionnaires' })).toBeVisible();
  fireEvent.click(screen.getByRole('button', { name: 'Create manually' }));
  fireEvent.change(screen.getByRole('textbox', { name: /Title.*English/ }), { target: { value: 'Unsaved fixture form' } });
  fireEvent.click(screen.getByRole('checkbox', { name: 'Urdu' }));
  fireEvent.change(screen.getByRole('textbox', { name: /Title.*Urdu/ }), { target: { value: '\u0646\u0645\u0648\u0646\u06c1' } });
  await preview('professional-questionnaires');
  fireEvent.click(screen.getByRole('link', { name: 'Patients & assignments' }));
  await screen.findByRole('heading', { name: 'Patients and assignments' });
  expect(screen.queryByRole('heading', { name: 'Your questionnaires' })).not.toBeInTheDocument();
  await preview('professional-patients');
  await act(async () => { window.history.back(); });
  await waitFor(() => expect(screen.getByRole('textbox', { name: /Title.*English/ })).toHaveValue('Unsaved fixture form'));
  expect(screen.getByRole('link', { name: 'Questionnaires' })).toHaveAttribute('aria-current', 'page');
  await act(async () => { window.history.forward(); });
  await screen.findByRole('heading', { name: 'Patients and assignments' });
  expect(window.location.search).toBe('?view=patients');
});
it.each(['submissions', 'analytics', 'appointments', 'messages'])('opens only the professional %s workflow', async view => {
  window.history.replaceState(null, '', '/professional?view=' + view);
  render(<ProfessionalWorkspace api={apiFor(true)} onSessionExpired={jest.fn()} />);
  await screen.findByRole('heading', { name: professionalViews.find(v => v.id === view)!.label, level: 1 });
  expect(screen.queryByRole('button', { name: 'Create manually' })).not.toBeInTheDocument();
  expect(screen.queryByRole('heading', { name: 'Public practice profile' })).not.toBeInTheDocument();
  if (view === 'submissions') await screen.findByRole('heading', { name: 'Submitted questionnaires' });
  await preview('professional-' + view);
});
it('resolves legacy anchors, explicit views and published version links', () => {
  window.history.replaceState(null, '', '/professional#practice-analytics');
  expect(viewFromLocation(professionalViews, 'dashboard')).toBe('analytics');
  window.history.replaceState(null, '', '/professional?version=fixture-version');
  expect(viewFromLocation(professionalViews, 'dashboard')).toBe('questionnaires');
  window.history.replaceState(null, '', '/patient?view=appointments#care');
  expect(viewFromLocation(patientViews, 'home')).toBe('appointments');
  window.history.replaceState(null, '', '/patient?view=unknown');
  expect(viewFromLocation(patientViews, 'home')).toBe('home');
});
it('allows General account notifications and keeps patient-only links out of its navigation', async () => {
  window.history.replaceState(null, '', '/patient?view=notifications#notifications');
  render(<PatientWorkspace api={apiFor()} onDenied={jest.fn()} />);
  await screen.findByRole('heading', { name: 'Notifications', level: 1 });
  expect(screen.queryByText('Active care relationship required')).not.toBeInTheDocument();
  expect(screen.queryByRole('link', { name: 'Questionnaires' })).not.toBeInTheDocument();
  expect(screen.queryByRole('heading', { name: 'Join a practice' })).not.toBeInTheDocument();
  await preview('general-notifications');
});
it.each(['home', 'experts', 'care', 'questionnaires', 'appointments', 'messages'])('focuses patient %s without revealing clinical information', async view => {
  window.history.replaceState(null, '', '/patient?view=' + view);
  const api = apiFor(false, true); render(<PatientWorkspace api={api} onDenied={jest.fn()} />);
  await screen.findByRole('heading', { name: patientViews.find(v => v.id === view)!.label, level: 1 });
  if (view !== 'home' && view !== 'experts') expect(screen.queryByRole('heading', { name: 'Join a practice' })).not.toBeInTheDocument();
  if (view === 'appointments') { await screen.findByRole('button', { name: 'Request appointment' }); expect(screen.queryByRole('button', { name: 'Send message' })).not.toBeInTheDocument(); }
  expect(screen.queryByText(/AI evaluation|Psychologist conclusion|Previous review revisions/)).not.toBeInTheDocument();
  expect((api.request as jest.Mock).mock.calls.some(([path]) => /evaluations|reviews|professional/.test(path))).toBe(false);
  await preview('patient-' + view);
});
// Labels intentionally reworded in the AI review layout (queued / failed with reason / completed).
it.each([['queued', 'Evaluation queued'], ['claimed', 'Evaluation in progress'], ['failed', 'Evaluation unavailable (unusable AI output): you can review the original answers manually'], ['completed', 'Evaluation completed']])('explains %s evaluation state and retains technical diagnostics', async (state, label) => {
  const api = apiFor(true);
  (api.request as jest.Mock).mockImplementation(async (path: string) => path.includes('/workspace') ? { submission: { patient_uid: 'fictional-patient', submitted_at: '2026-10-21T00:00:00Z', answers: [] }, questionnaire: { content: emptyContent() }, evaluation: { id: 'fixture-evaluation', interpretation: null, validated_scores: [], evidence: [] }, job: { state, ...(state === 'failed' ? { failure_code: 'invalid_output' } : {}) }, review_revision: 0 } : { items: [], next_cursor: null });
  render(<SubmissionReview id="fixture-submission" api={api} onError={jest.fn()} />);
  await screen.findByText(label);
  expect(screen.getByText(state, { selector: 'code' })).toBeInTheDocument();
  if (state === 'failed') expect(screen.getByText('invalid_output', { selector: 'code' })).toBeInTheDocument();
  expect(screen.getByText(/No AI interpretation is available/)).toBeVisible();
  await preview('review-' + state);
});

it('keeps an open patient attempt and its latest answers when navigating between care views', async () => {
  window.history.replaceState(null, '', '/patient?view=questionnaires');
  const api = apiFor(false, true);
  const content = emptyContent(); content.title.en = 'Fictional assigned form'; content.questions[0].prompt.en = 'Fictional answer';
  (api.request as jest.Mock).mockImplementation(async (path: string, method?: string) => {
    if (path.endsWith('/assignments/fixture-assignment')) return { assignment: { id: 'fixture-assignment', relationship_id: 'fixture-relationship' }, attempt: { id: 'fixture-attempt', revision: 1, answers: [] }, questionnaire: content };
    if (method === 'PATCH') return { revision: 2 };
    if (path.includes('capabilities')) return caps(false, true);
    if (path.includes('/patient/assignments')) return { items: [{ id: 'fixture-assignment', relationship_id: 'fixture-relationship', state: 'assigned', title: { en: 'Fictional assigned form' } }], next_cursor: null };
    return { items: [], next_cursor: null };
  });
  render(<PatientWorkspace api={api} onDenied={jest.fn()} />);
  fireEvent.click(await screen.findByRole('button', { name: 'Start questionnaire' }));
  fireEvent.change(await screen.findByRole('textbox', { name: 'Fictional answer' }), { target: { value: 'Preserved fictional answer' } });
  await preview('patient-runner');
  fireEvent.click(screen.getByRole('link', { name: 'My Care / Overview' }));
  await screen.findByRole('heading', { name: 'Your care is active' });
  expect(screen.queryByRole('textbox', { name: 'Fictional answer' })).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole('link', { name: 'Questionnaires' }));
  expect(await screen.findByRole('textbox', { name: 'Fictional answer' })).toHaveValue('Preserved fictional answer');
});

it('explains account access without a dead signup action', async () => {
  render(<AccountApp />);
  expect(screen.getByRole('heading', { name: 'KOI Care account' })).toBeVisible();
  fireEvent.click(screen.getByText('How KOI identities and access work'));
  for (const label of ['Anonymous companion', 'Registered care account', 'Active patient access', 'Verified psychologist access']) expect(screen.getByText(label)).toBeVisible();
  expect(screen.queryByRole('link', { name: /sign up|register/i })).not.toBeInTheDocument();
  expect(screen.getByRole('textbox', { name: 'Email' })).toHaveAttribute('autocomplete', 'username');
  await preview('account');
});
it('gives a General account a useful home with invitations and pending applications', async () => {
  window.history.replaceState(null, '', '/patient');
  render(<PatientWorkspace api={apiFor()} onDenied={jest.fn()} />);
  await screen.findByRole('heading', { name: 'Start your care journey' });
  fireEvent.click(screen.getByText('Have an invitation code?'));
  expect(screen.getByRole('button', { name: 'Accept invitation' })).toBeDisabled();
  expect(await screen.findByText('Waiting for practice review')).toBeVisible();
  expect(screen.getAllByRole('link', { name: 'Find a Psychologist' })).toHaveLength(2);
  await preview('general-home');
});
