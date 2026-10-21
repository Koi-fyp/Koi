import React from 'react';
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import QuestionnaireRunner from '@/components/patient/QuestionnaireRunner';
import { FeedbackProviders } from '@/components/ui/feedback';
import { PlatformClientError, type ProfessionalApi } from '@/lib/platform/client';
import type { PatientDetail } from '@/lib/platform/patient-types';
import { illustrations } from '@/lib/platform/content';
const initial: Extract<PatientDetail, { attempt: unknown }> = {
  assignment: { id: 'a', relationship_id: 'r', organization_id: 'o', questionnaire_version_id: 'v', attempt_id: 't', title: { en: 'Form', ur: 'سوالنامہ' }, state: 'assigned', created_at: '2026-10-19T00:00:00Z' },
  questionnaire: { version_id: 'v', schema_version: '0.5.0', title: { en: 'Form', ur: 'سوالنامہ' }, locales: ['en', 'ur'], questions: [{ id: 'q', type: 'short_text', required: true, max_length: 100, prompt: { en: 'Your answer', ur: 'آپ کا جواب' } }, { id: 'picture', type: 'image_single_choice', required: false, prompt: { en: 'Shape', ur: 'شکل' }, options: illustrations.slice(0, 2).map((a, i) => ({ id: `o${i}`, label: { en: i ? 'Square' : 'Circle', ur: i ? 'مربع' : 'دائرہ' }, asset: a.reference })) }] },
  attempt: { id: 't', assignment_id: 'a', patient_uid: 'p', version_id: 'v', status: 'not_started', answers: [], revision: 0, server_updated_at: '2026-10-19T00:00:00Z' },
};
beforeEach(() => jest.spyOn(window, 'confirm').mockReturnValue(true)); afterEach(() => jest.restoreAllMocks());
it('autosaves text and pictures, resumes, restarts and returns only a submission acknowledgement', async () => {
  let saved: any[] = [], revision = 0;
  const request = jest.fn(async (path, method, body) => {
    if (method === 'PATCH') { expect(body.expected_revision).toBe(revision); saved = body.answers; return { revision: ++revision }; }
    return { attempt_id: 't', assignment_id: 'a', submitted_at: '2026-10-19T12:00:00Z', status: 'submitted' };
  });
  const api = { request, dispose: jest.fn() } as ProfessionalApi;
  const view = render(<QuestionnaireRunner api={api} initial={initial} onClose={jest.fn()} onDenied={jest.fn()} />);
  fireEvent.change(screen.getByRole('textbox', { name: 'Your answer' }), { target: { value: 'Saved response' } }); fireEvent.click(screen.getByLabelText('Circle'));
  await waitFor(() => expect(saved).toHaveLength(2), { timeout: 2500 });
  view.unmount(); render(<QuestionnaireRunner api={api} initial={{ ...initial, attempt: { ...initial.attempt, answers: saved, revision } }} onClose={jest.fn()} onDenied={jest.fn()} />, { wrapper: FeedbackProviders });
  expect(screen.getByRole('textbox', { name: 'Your answer' })).toHaveValue('Saved response');
  // Themed dialog replaced window.confirm: confirm the restart inside it.
  fireEvent.click(screen.getByRole('button', { name: 'Restart questionnaire' }));
  fireEvent.click(within(await screen.findByRole('alertdialog', { name: 'Restart this questionnaire?' })).getByRole('button', { name: 'Restart questionnaire' })); await waitFor(() => expect(screen.getByRole('textbox', { name: 'Your answer' })).toHaveValue(''));
  fireEvent.change(screen.getByRole('textbox', { name: 'Your answer' }), { target: { value: 'Final response' } }); fireEvent.click(screen.getByRole('button', { name: 'Save answers' }));
  await waitFor(() => expect(screen.getByRole('button', { name: 'Review before submitting' })).toBeEnabled()); fireEvent.click(screen.getByRole('button', { name: 'Review before submitting' }));
  expect(screen.getByRole('textbox', { name: 'Your answer' })).toBeDisabled(); fireEvent.click(screen.getByRole('button', { name: 'Confirm final submission' }));
  await screen.findByRole('heading', { name: 'Questionnaire submitted' }); expect(screen.queryByText('Final response')).not.toBeInTheDocument(); expect(document.body.textContent).not.toMatch(/\b(score|evaluation|AI|interpretation)\b/i);
});
it('keeps conflicting local edits until deliberate reconciliation and renders Urdu RTL', async () => {
  const request = jest.fn(async (_path, method) => { if (method === 'PATCH') throw new PlatformClientError(409, 'conflict'); return { ...initial, attempt: { ...initial.attempt, revision: 1, answers: [{ question_id: 'q', type: 'short_text', value: 'Other device' }] } }; });
  render(<QuestionnaireRunner api={{ request, dispose: jest.fn() } as ProfessionalApi} initial={initial} onClose={jest.fn()} onDenied={jest.fn()} />);
  fireEvent.change(screen.getByRole('textbox', { name: 'Your answer' }), { target: { value: 'Local changes' } }); fireEvent.click(screen.getByRole('button', { name: 'Save answers' }));
  await screen.findByRole('button', { name: 'Use saved answers' }); expect(screen.getAllByRole('textbox', { name: 'Your answer' }).some(e => (e as HTMLInputElement).value === 'Local changes')).toBe(true);
  fireEvent.click(screen.getByRole('button', { name: 'Use saved answers' })); expect(screen.getByRole('textbox', { name: 'Your answer' })).toHaveValue('Other device');
  fireEvent.change(screen.getByRole('combobox'), { target: { value: 'ur' } }); expect(screen.getByRole('textbox', { name: 'آپ کا جواب' }).closest('[dir]')).toHaveAttribute('dir', 'rtl');
});
it('unmounts protected answers when relationship access is denied', async () => {
  const request = jest.fn(async () => { throw new PlatformClientError(403, 'forbidden'); }); let view: ReturnType<typeof render>;
  const denied = jest.fn(() => view.unmount());
  view = render(<QuestionnaireRunner api={{ request, dispose: jest.fn() } as ProfessionalApi} initial={initial} onClose={jest.fn()} onDenied={denied} />);
  fireEvent.change(screen.getByRole('textbox', { name: 'Your answer' }), { target: { value: 'PRIVATE PATIENT TEXT' } }); fireEvent.click(screen.getByRole('button', { name: 'Save answers' }));
  await waitFor(() => expect(denied).toHaveBeenCalled()); expect(document.body.textContent).not.toContain('PRIVATE PATIENT TEXT');
});
