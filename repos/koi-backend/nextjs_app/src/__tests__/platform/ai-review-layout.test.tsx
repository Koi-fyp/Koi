import React from 'react';
import { fireEvent, render, screen, within } from '@testing-library/react';
import SubmissionReview from '@/components/professional/SubmissionReview';
import { FeedbackProviders } from '@/components/ui/feedback';
import { answerText, evaluationStateText, evidenceCoverage, parseInterpretation } from '@/lib/platform/interpretation';
import { newQuestion } from '@/lib/platform/content';
import type { SubmissionWorkspace } from '@/lib/platform/professional-types';
import type { ProfessionalApi } from '@/lib/platform/client';

const v3 = `## Summary
The patient describes trouble falling asleep on most nights.

## Key observations
- Sleep onset takes over an hour (Q1)
- Reports feeling rested on weekends

## Themes
- Evening screen use

## Points to clarify
1. How long has this pattern lasted?

## Missing information
- No answer about caffeine

## Limitations
AI-generated from questionnaire answers only. Not a diagnosis.`;
const mock = `FICTIONAL MOCK EVALUATION
Summary: Mock summary of the submitted answers.
Key observations:
* Mock observation one
Limitations: Canned mock output for local testing.`;
const prose = 'In summary, the answers suggest a stable week. Themes were not analysed.';

describe('interpretation parsing', () => {
  it('splits a v3-style text into the six known sections with bullets', () => {
    const parsed = parseInterpretation(v3);
    expect(parsed.structured).toBe(true);
    expect(parsed.sections.map(s => s.title)).toEqual(['Summary', 'Key observations', 'Themes', 'Points to clarify', 'Missing information', 'Limitations']);
    expect(parsed.sections[1].items).toEqual(['Sleep onset takes over an hour (Q1)', 'Reports feeling rested on weekends']);
    expect(parsed.sections[3].items).toEqual(['How long has this pattern lasted?']);
    expect(parsed.sections[5].paragraphs).toEqual(['AI-generated from questionnaire answers only. Not a diagnosis.']);
  });
  it('handles a canned mock text with inline "Heading:" lines and keeps its preface', () => {
    const parsed = parseInterpretation(mock);
    expect(parsed.preface).toEqual(['FICTIONAL MOCK EVALUATION']);
    expect(parsed.sections.map(s => [s.title, s.paragraphs, s.items])).toEqual([['Summary', ['Mock summary of the submitted answers.'], []], ['Key observations', [], ['Mock observation one']], ['Limitations', ['Canned mock output for local testing.'], []]]);
  });
  it('leaves prose without headings unstructured', () => {
    expect(parseInterpretation(prose).structured).toBe(false);
    expect(parseInterpretation(null).structured).toBe(false);
  });
  it('quotes answers exactly, maps choices to labels and never invents one', () => {
    const choice = newQuestion('single_choice', ['en']); choice.options![0].label = { en: 'Most nights' };
    expect(answerText(choice, { question_id: choice.id, type: 'single_choice', value: choice.options![0].id }, 'en')).toBe('Most nights');
    expect(answerText(undefined, { question_id: 'q', type: 'yes_no', value: false }, 'en')).toBe('No');
    expect(answerText(undefined, { question_id: 'q', type: 'short_text', value: '  ' }, 'en')).toBeNull();
    expect(answerText(undefined, undefined, 'en')).toBeNull();
    expect(evidenceCoverage({ evidence: [{ question_id: 'a', answer_index: 0 }, { question_id: 'a', answer_index: 0 }, { question_id: 'missing', answer_index: 0 }] }, [{ question_id: 'a', type: 'short_text', value: 'x' }, { question_id: 'b', type: 'short_text', value: 'y' }])).toEqual({ cited: 1, total: 2 });
  });
  it('words pending and failed states clearly', () => {
    expect(evaluationStateText({ state: 'queued' }).label).toBe('Evaluation queued');
    expect(evaluationStateText({ state: 'failed', failure_code: 'provider_unavailable' }).label).toBe('Evaluation unavailable (AI service unavailable): you can review the original answers manually');
  });
});

describe('submission review layout', () => {
  const first = newQuestion('short_text', ['en']), second = newQuestion('short_text', ['en']);
  first.prompt = { en: 'How long does it take to fall asleep?' }; second.prompt = { en: 'Anything else?' };
  let value: SubmissionWorkspace, api: ProfessionalApi;
  beforeEach(() => {
    value = { questionnaire: { id: 'version', questionnaire_id: 'q', organization_id: 'org', psychologist_uid: 'psy', source_revision: 1, content: { kind: 'custom_questionnaire', validation_status: 'not_validated', origin: 'manual', title: { en: 'Sleep check' }, locales: ['en'], questions: [first, second] }, content_sha256: '0'.repeat(64), published_at: '2026-10-21T00:00:00Z', schema_version: '0.5.0' },
      submission: { id: 'submission', organization_id: 'org', relationship_id: 'r', assignment_id: 'a', attempt_id: 't', patient_uid: 'patient', questionnaire_version_id: 'version', submitted_at: '2026-10-21T00:00:00Z', answers: [{ question_id: first.id, type: 'short_text', value: 'Usually more than an hour' }, { question_id: second.id, type: 'short_text', value: 'No' }] },
      evaluation: { id: 'evaluation', organization_id: 'org', submission_id: 'submission', questionnaire_version_id: 'version', validated_scores: [], interpretation: v3, evidence: [{ question_id: first.id, answer_index: 0 }], review_status: 'unreviewed', created_at: '2026-10-21T00:00:00Z' },
      job: { id: 'job', organization_id: 'org', kind: 'evaluate', state: 'completed', created_at: '2026-10-21T00:00:00Z', updated_at: '2026-10-21T00:00:00Z' }, review_revision: 0 } as SubmissionWorkspace;
    api = { dispose: jest.fn(), request: jest.fn(async (path: string) => path.endsWith('/workspace') ? value : { items: [], next_cursor: null }) as any };
  });
  it('labels AI output, shows coverage, the sections and evidence quoting the real answer', async () => {
    render(<SubmissionReview id="submission" api={api} onError={jest.fn()} />, { wrapper: FeedbackProviders });
    expect(await screen.findByText('AI-generated · expert review required')).toBeInTheDocument();
    expect(screen.getByText('Answers cited by the AI').closest('.care-tile')).toHaveTextContent('1 / 2');
    const interpretation = screen.getByRole('region', { name: 'AI interpretation' });
    for (const title of ['Summary', 'Key observations', 'Themes', 'Points to clarify', 'Missing information', 'Limitations']) expect(within(interpretation).getByRole('region', { name: title })).toBeInTheDocument();
    expect(within(interpretation).getByText('Sleep onset takes over an hour (Q1)').tagName).toBe('LI');
    const evidence = screen.getByRole('region', { name: 'Supporting evidence' });
    expect(within(evidence).getByText('How long does it take to fall asleep?')).toBeInTheDocument();
    expect(within(evidence).getByText('Usually more than an hour').tagName).toBe('BLOCKQUOTE');
    fireEvent.click(screen.getByRole('button', { name: 'Refresh evaluation' }));
    expect(await screen.findByText('Evaluation refreshed')).toBeInTheDocument();
  });
  it('falls back to the raw text with preserved line breaks, and words a failure', async () => {
    value.evaluation.interpretation = prose; value.job = { ...value.job, state: 'failed', failure_code: 'invalid_output' };
    render(<SubmissionReview id="submission" api={api} onError={jest.fn()} />);
    expect(await screen.findByText('Evaluation unavailable (unusable AI output): you can review the original answers manually')).toBeInTheDocument();
    expect(screen.getByText(prose)).toHaveStyle({ whiteSpace: 'pre-wrap' });
  });
});
