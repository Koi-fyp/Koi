import React from 'react';
import { act, cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import CareLink from '@/components/platform/CareLink';
import WorkspaceFrame, { professionalViews } from '@/components/platform/WorkspaceFrame';
import SubmissionReview from '@/components/professional/SubmissionReview';
import PatientManagement from '@/components/professional/PatientManagement';
import { illustrations, newQuestion } from '@/lib/platform/content';
import type { QuestionType, VersionDTO } from '@/lib/platform/types';
import type { SubmissionWorkspace, Decision } from '@/lib/platform/professional-types';
import type { ProfessionalApi } from '@/lib/platform/client';
const types: QuestionType[] = ['short_text', 'yes_no', 'single_choice', 'multi_choice', 'likert', 'image_single_choice', 'image_multi_choice'];
function snapshot(): VersionDTO {
  return { id: 'published-known', questionnaire_id: 'form-known', organization_id: 'org', psychologist_uid: 'psychologist', source_revision: 4, content: { kind: 'custom_questionnaire', validation_status: 'not_validated', origin: 'manual', title: { en: 'Wellbeing check-in', ur: '\u062c\u0627\u0626\u0632\u06c1' }, locales: ['en', 'ur'], questions: types.map(type => {
    const question = newQuestion(type, ['en', 'ur']); question.prompt = { en: type + ' original question', ur: '\u0633\u0648\u0627\u0644 ' + type };
    question.options?.forEach((option, index) => { option.label = { en: type + ' choice ' + index, ur: '\u062c\u0648\u0627\u0628 ' + index }; }); return question;
  }) }, content_sha256: '0'.repeat(64), published_at: '2026-10-21T10:00:00Z', schema_version: '0.5.0' };
}
function reviewRow(revision: number, decision: Decision['decision'] = 'feedback'): Decision {
  return { decision, review: { id: 'review-' + revision, organization_id: 'org', evaluation_id: 'evaluation', reviewer_uid: 'psychologist', revision, conclusion: 'Saved conclusion ' + revision, feedback: 'Saved feedback ' + revision, created_at: '2026-10-21T12:00:00Z' } };
}
let value: SubmissionWorkspace, rows: Decision[], request: jest.Mock, api: ProfessionalApi;
beforeEach(() => {
  const questionnaire = snapshot();
  value = { questionnaire, submission: { id: 'submission', organization_id: 'org', patient_uid: 'patient-fixture', relationship_id: 'relationship', assignment_id: 'assignment', attempt_id: 'attempt', questionnaire_version_id: questionnaire.id, submitted_at: '2026-10-21T11:00:00Z', answers: questionnaire.content.questions.map(question => ({ question_id: question.id, type: question.type, value: question.type === 'short_text' ? '  Exact original text\nwith a second line.  ' : question.type === 'yes_no' ? true : question.type.includes('multi') ? question.options!.map(option => option.id) : question.options![1].id })) }, evaluation: { id: 'evaluation', organization_id: 'org', submission_id: 'submission', questionnaire_version_id: questionnaire.id, validated_scores: [], interpretation: undefined, evidence: [], review_status: 'unreviewed', created_at: '2026-10-21T11:00:00Z' }, job: { id: 'job', organization_id: 'org', kind: 'evaluate', state: 'queued', created_at: '2026-10-21T11:00:00Z', updated_at: '2026-10-21T11:00:00Z' }, review_revision: 2 };
  rows = [reviewRow(2), reviewRow(1, 'reject')];
  request = jest.fn(async (path: string, method = 'GET', body?: any) => {
    if (path.endsWith('/workspace')) return value;
    if (path === '/api/v1/professional/review-decisions' && method === 'POST') { const row = reviewRow(value.review_revision + 1, body.decision); row.review.conclusion = body.conclusion; row.review.feedback = body.feedback; rows = [row, ...rows]; value = { ...value, review_revision: row.review.revision }; return row; }
    if (path.includes('/review-decisions')) return { items: rows, next_cursor: null };
    if (path.includes('/questionnaire-versions/')) return questionnaire;
    if (path.includes('/analytics')) return { series: [{ questionnaire_version_id: questionnaire.id, enrolled: 1, submitted: 1, points: [] }] };
    if (path.includes('/patient-relationships?')) return { items: [{ id: 'relationship', organization_id: 'org', patient_uid: 'patient-fixture', state: 'active', revision: 1, activated_at: '2026-10-21T11:00:00Z' }], next_cursor: null };
    if (path === '/api/v1/professional/assignments' && method === 'POST') return { assignment_ids: ['fixture-assignment'] };
    return { items: [], next_cursor: null };
  });
  api = { request: request as any, dispose: jest.fn() };
  jest.spyOn(window, 'confirm').mockReturnValue(true);
  Object.defineProperty(HTMLElement.prototype, 'scrollIntoView', { configurable: true, value: jest.fn() });
  window.history.replaceState(null, '', '/professional?view=submissions');
});
afterEach(() => { cleanup(); jest.restoreAllMocks(); });
const mountReview = () => render(<WorkspaceFrame base="/professional" views={professionalViews} view="submissions"><SubmissionReview id="submission" api={api} onError={jest.fn()} /></WorkspaceFrame>);
it('uses semantic Neo link variants without changing their destinations', () => {
  render(<><CareLink variant="primary" href="/professional?view=questionnaires#professional-questionnaires">Manage questionnaires</CareLink><CareLink variant="secondary" href="/account">Account</CareLink><CareLink href="#context">Context</CareLink></>);
  expect(screen.getByRole('link', { name: 'Manage questionnaires' })).toHaveClass('neo-btn-primary', 'care-link--primary');
  expect(screen.getByRole('link', { name: 'Manage questionnaires' })).toHaveAttribute('href', '/professional?view=questionnaires#professional-questionnaires');
  expect(screen.getByRole('link', { name: 'Account' })).toHaveClass('neo-btn-ghost', 'care-link--secondary');
  expect(screen.getByRole('link', { name: 'Context' })).toHaveClass('care-link--compact');
});
it('keeps every original question type, text response and image selection immutable with Urdu handling', async () => {
  const original = JSON.stringify(value.submission.answers); mountReview();
  await screen.findByRole('heading', { name: 'Wellbeing check-in' });
  const answers = screen.getByRole('region', { name: "Patient's original submitted answers" });
  expect(answers.querySelectorAll('fieldset')).toHaveLength(types.length);
  expect(within(answers).getByRole('textbox', { name: 'short_text original question' })).toHaveValue('  Exact original text\nwith a second line.  ');
  for (const control of answers.querySelectorAll('fieldset input,fieldset textarea')) expect(control).toBeDisabled();
  const picture = within(answers).getByRole('group', { name: /image_single_choice original question/ });
  expect(picture.querySelectorAll('input:checked')).toHaveLength(1);
  const selected = picture.querySelector<HTMLInputElement>('input:checked')!;
  expect(selected.closest('label')?.querySelector('img')?.getAttribute('src')).toBe(illustrations[1].web_path);
  fireEvent.change(screen.getByRole('combobox', { name: 'Answer language' }), { target: { value: 'ur' } });
  expect(answers.querySelector('[dir=rtl]')).toHaveAttribute('lang', 'ur');
  expect(JSON.stringify(value.submission.answers)).toBe(original);
  expect(request.mock.calls.every(([, method]) => !method || method === 'GET')).toBe(true);
});
it.each(['queued', 'failed'] as const)('explains disabled review actions and allows manual review while evaluation is %s', async state => {
  value.job.state = state; if (state === 'failed') value.job.failure_code = 'invalid_output';
  mountReview(); await screen.findByRole('heading', { name: 'Psychologist review' });
  const actions = ['Approve review', 'Reject evaluation', 'Save feedback'].map(name => screen.getByRole('button', { name }));
  for (const action of actions) { expect(action).toBeDisabled(); expect(action).toHaveAccessibleDescription(/Enter a psychologist conclusion/); }
  expect(screen.getByText(/pending or unavailable AI evaluation does not prevent manual review/)).toBeVisible();
  fireEvent.change(screen.getByRole('textbox', { name: 'Review feedback' }), { target: { value: 'Feedback alone does not enable review' } });
  expect(actions[2]).toBeDisabled();
  fireEvent.change(screen.getByRole('textbox', { name: 'Psychologist conclusion' }), { target: { value: '   ' } }); expect(actions[0]).toBeDisabled();
  fireEvent.change(screen.getByRole('textbox', { name: 'Psychologist conclusion' }), { target: { value: 'Manual fixture conclusion' } });
  for (const action of actions) expect(action).toBeEnabled();
  expect(screen.getByText(state, { selector: 'code' })).toBeInTheDocument();
});
it.each(['Approve review', 'Reject evaluation', 'Save feedback'])('saves %s as an immutable revision with confirmation and unchanged answers', async label => {
  const original = JSON.stringify(value.submission.answers); mountReview(); await screen.findByRole('heading', { name: 'Psychologist review' });
  fireEvent.change(screen.getByRole('textbox', { name: 'Psychologist conclusion' }), { target: { value: 'My exact fixture conclusion' } });
  fireEvent.change(screen.getByRole('textbox', { name: 'Review feedback' }), { target: { value: 'My optional fixture feedback' } });
  fireEvent.click(screen.getByRole('button', { name: label }));
  await screen.findByText('Review revision 3 saved. Original answers and interpretation are preserved.');
  const post = request.mock.calls.find(([path, method]) => path === '/api/v1/professional/review-decisions' && method === 'POST');
  expect(post?.[2]).toEqual({ organization_id: 'org', evaluation_id: 'evaluation', expected_review_revision: 2, conclusion: 'My exact fixture conclusion', feedback: 'My optional fixture feedback', decision: label === 'Approve review' ? 'approve' : label === 'Reject evaluation' ? 'reject' : 'feedback' });
  expect(JSON.stringify(value.submission.answers)).toBe(original);
  expect(screen.getByRole('textbox', { name: 'Psychologist conclusion' })).toHaveValue('');
  const latest = await screen.findByText(/Revision 3:/, { selector: 'summary' }); fireEvent.click(latest);
  expect(screen.getByText('My exact fixture conclusion')).toBeVisible();
  expect(screen.getByText('My optional fixture feedback')).toBeVisible();
});
it('navigates review sections, focuses destinations and restores the section through Back/Forward', async () => {
  mountReview(); await screen.findByRole('navigation', { name: 'Submission review sections' });
  fireEvent.click(screen.getByRole('link', { name: '1. Submission overview' }));
  await waitFor(() => expect(document.activeElement?.id).toBe('review-submission-overview'));
  fireEvent.click(screen.getByRole('link', { name: '4. Psychologist review' }));
  await waitFor(() => expect(document.activeElement?.id).toBe('review-submission-review'));
  expect(screen.getByRole('link', { name: '4. Psychologist review' })).toHaveAttribute('aria-current', 'location');
  expect(window.location.search).toBe('?view=submissions');
  await act(async () => { window.history.back(); });
  await waitFor(() => expect(document.activeElement?.id).toBe('review-submission-overview'));
  await act(async () => { window.history.forward(); });
  await waitFor(() => expect(document.activeElement?.id).toBe('review-submission-review'));
});
it('preserves review text when saving fails', async () => {
  const original = request.getMockImplementation()!;
  request.mockImplementation(async (path, method, body) => { if (method === 'POST') throw new Error('fixture conflict'); return original(path, method, body); });
  mountReview(); await screen.findByRole('heading', { name: 'Psychologist review' });
  fireEvent.change(screen.getByRole('textbox', { name: 'Psychologist conclusion' }), { target: { value: 'Keep my conclusion' } });
  fireEvent.click(screen.getByRole('button', { name: 'Approve review' }));
  await screen.findByText(/Review save was not confirmed/);
  expect(screen.getByRole('textbox', { name: 'Psychologist conclusion' })).toHaveValue('Keep my conclusion');
});
it('offers authorized version names and sends the real selected ID with the existing assignment target', async () => {
  render(<PatientManagement api={api} organizationId="org" onDenied={jest.fn()} />);
  const option = await screen.findByRole('option', { name: 'Wellbeing check-in - Revision 4 - English, Urdu' });
  expect(option).toHaveValue('published-known');
  fireEvent.click(await screen.findByRole('checkbox', { name: 'Select patient-fixture for assignment' }));
  fireEvent.change(screen.getByRole('combobox', { name: 'Published questionnaire' }), { target: { value: 'published-known' } });
  fireEvent.click(screen.getByRole('button', { name: 'Assign published questionnaire' }));
  await screen.findByText('1 independent assignments created.');
  expect(request).toHaveBeenCalledWith('/api/v1/professional/assignments', 'POST', { organization_id: 'org', questionnaire_version_id: 'published-known', target: { kind: 'selected', relationship_ids: ['relationship'] } });
});
it('keeps a clearly labeled ID fallback without inventing a published catalogue endpoint', async () => {
  render(<PatientManagement api={api} organizationId="org" onDenied={jest.fn()} />);
  fireEvent.change(screen.getByRole('combobox', { name: 'Published questionnaire' }), { target: { value: '__manual__' } });
  expect(await screen.findByRole('textbox', { name: 'Published questionnaire version ID' })).toBeVisible();
  expect(screen.getByText(/current API does not list every previously published version/)).toBeVisible();
  expect(request.mock.calls.every(([path]) => !/published-versions|version-catalogue/.test(path))).toBe(true);
});

it('distinguishes unavailable history from an empty history and retains the original answers', async () => {
  const original = request.getMockImplementation()!;
  request.mockImplementation(async (path, method, body) => { if (String(path).includes('/review-decisions')) throw new Error('history fixture unavailable'); return original(path, method, body); });
  mountReview();
  await screen.findByText('Review history could not be refreshed. Previously loaded revisions are retained.');
  expect(screen.queryByText('No review revisions yet.')).not.toBeInTheDocument();
  expect(screen.getByRole('textbox', { name: 'short_text original question' })).toHaveValue('  Exact original text\nwith a second line.  ');
});
it('includes known unused published versions but never offers a version from another organization', async () => {
  const known = { ...snapshot(), id: 'known-unused', content: { ...snapshot().content, title: { en: 'Known unused questionnaire' } } };
  const foreign = { ...snapshot(), id: 'foreign-version', organization_id: 'another-org', content: { ...snapshot().content, title: { en: 'Foreign questionnaire' } } };
  const original = request.getMockImplementation()!;
  request.mockImplementation(async (path, method, body) => {
    if (String(path).includes('/analytics')) return { series: [{ questionnaire_version_id: foreign.id }] };
    if (String(path).includes('/questionnaire-versions/')) return foreign;
    return original(path, method, body);
  });
  render(<PatientManagement api={api} organizationId="org" knownVersions={[known, foreign]} onDenied={jest.fn()} />);
  expect(await screen.findByRole('option', { name: /Known unused questionnaire/ })).toHaveValue('known-unused');
  await screen.findByText(/Some version details are unavailable/);
  expect(screen.queryByRole('option', { name: /Foreign questionnaire/ })).not.toBeInTheDocument();
});
