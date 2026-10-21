'use client';
import { useEffect, useRef, useState } from 'react';
import NeoButton from '@/components/ui/NeoButton';
import NeoCard from '@/components/ui/NeoCard';
import CareLink from '@/components/platform/CareLink';
import { useWorkspaceFragment } from '@/components/platform/WorkspaceFrame';
import { useCareReveal } from '@/components/platform/care-focus';
import type { ProfessionalApi } from '@/lib/platform/client';
import type { Decision, ReviewDecision, SubmissionWorkspace } from '@/lib/platform/professional-types';
import type { Page } from '@/lib/platform/patient-types';
import type { Locale } from '@/lib/platform/types';
import { localeNames } from '@/lib/platform/content';
import QuestionFields from '@/components/patient/QuestionFields';

const decisionNames: Record<ReviewDecision, string> = { approve: 'Approved', reject: 'Rejected', feedback: 'Feedback recorded' };
export default function SubmissionReview({ id, api, onError }: { id: string; api: ProfessionalApi; onError: (error: unknown) => void }) {
  const [value, setValue] = useState<SubmissionWorkspace | null>(null), [history, setHistory] = useState<Decision[]>([]), [cursor, setCursor] = useState<string | null>(null);
  const [conclusion, setConclusion] = useState(''), [feedback, setFeedback] = useState(''), [busy, setBusy] = useState(false), [message, setMessage] = useState(''), [locale, setLocale] = useState<Locale>('en');
  const [loadError, setLoadError] = useState(false), [reviewError, setReviewError] = useState(''), [historyState, setHistoryState] = useState<'loading' | 'ready' | 'error'>('loading');
  const alive = useRef(true), running = useRef(false);
  const fragment = useWorkspaceFragment(), sectionId = (part: string) => `review-${id}-${part}`;
  const sections = [['overview', 'Submission overview'], ['answers', 'Original answers'], ['evaluation', 'AI evaluation & evidence'], ['review', 'Psychologist review'], ['history', 'Review history']] as const;
  const isSection = sections.some(([part]) => sectionId(part) === fragment);
  useCareReveal(fragment, fragment || null, !!value && isSection);
  const historyPage = async (eid: string, next?: string) => {
    setHistoryState('loading');
    try {
      const result = await api.request<Page<Decision>>(`/api/v1/professional/evaluations/${eid}/review-decisions${next ? `?cursor=${encodeURIComponent(next)}` : ''}`);
      if (alive.current) { setHistory(old => next ? [...old, ...result.items] : result.items); setCursor(result.next_cursor); setHistoryState('ready'); }
    } catch (error) { if (alive.current) setHistoryState('error'); throw error; }
  };
  const load = async () => {
    setLoadError(false);
    const result = await api.request<SubmissionWorkspace>(`/api/v1/professional/submissions/${id}/workspace`);
    if (!alive.current) return;
    setValue(result); setLocale(current => result.questionnaire.content.locales.includes(current) ? current : result.questionnaire.content.locales[0]);
    await historyPage(result.evaluation.id);
  };
  const loadFailure = (error: unknown) => { if (alive.current) { setLoadError(true); onError(error); } };
  useEffect(() => { alive.current = true; void load().catch(loadFailure); return () => { alive.current = false; }; }, [id, api]);
  if (!value && loadError) return <NeoCard className="professional-card"><p role="alert">The submission could not be loaded. Your access or the service may have changed.</p><NeoButton onClick={() => void load().catch(loadFailure)}>Retry submission</NeoButton></NeoCard>;
  if (!value) return <p role="status"><span className="neo-spinner" aria-hidden="true" />Loading protected submission...</p>;
  const decide = async (decision: ReviewDecision) => {
    if (running.current || !conclusion.trim()) return;
    if (!window.confirm(`Save this ${decision} decision as an immutable review revision?`)) return;
    running.current = true; setBusy(true); setMessage(''); setReviewError('');
    try {
      const saved = await api.request<Decision>('/api/v1/professional/review-decisions', 'POST', { organization_id: value.submission.organization_id, evaluation_id: value.evaluation.id, expected_review_revision: value.review_revision, conclusion, ...(feedback.trim() ? { feedback } : {}), decision });
      if (alive.current) {
        setConclusion(''); setFeedback('');
        setMessage(`Review revision ${saved.review.revision} saved. Original answers and interpretation are preserved.`);
        await load().catch(error => { if (alive.current) { setReviewError('Your review was saved, but the latest submission or history could not be refreshed. Refresh before another review.'); onError(error); } });
      }
    } catch (error) { if (alive.current) { setReviewError('Review save was not confirmed. Your conclusion and feedback are still here. Check the workspace message before retrying.'); onError(error); } }
    finally { running.current = false; if (alive.current) setBusy(false); }
  };
  const title = value.questionnaire.content.title[locale] ?? value.questionnaire.content.title[value.questionnaire.content.locales[0]];
  const stateLabel = value.job.state === 'queued' ? 'Pending evaluation' : value.job.state === 'claimed' ? 'Evaluation in progress' : value.job.state === 'failed' ? 'Evaluation unavailable' : value.job.state === 'completed' ? 'Evaluation processing completed' : 'Evaluation status unavailable';
  return <NeoCard className="professional-card" aria-label="Protected submission review" aria-busy={busy}>
    <header className="professional-stack"><h2>Submission and clinician review</h2><p className="professional-muted">Professional workspace only. Submitted answers stay read-only; saved review revisions are retained.</p></header>
    <nav className="care-review-nav" aria-label="Submission review sections">{sections.map(([part, label], index) => <CareLink key={part} href={`#${sectionId(part)}`} aria-current={fragment === sectionId(part) ? 'location' : undefined}>{index + 1}. {label}</CareLink>)}</nav>

    <section id={sectionId('overview')} tabIndex={-1} className="care-review-section" aria-labelledby={sectionId('overview-heading')}>
      <h3 id={sectionId('overview-heading')}>Submission overview</h3>
      <h4 className="care-submission-title" dir={locale === 'ur' ? 'rtl' : 'ltr'} lang={locale}>{title}</h4>
      <dl className="care-review-summary"><div><dt>Patient account</dt><dd><bdi>{value.submission.patient_uid}</bdi></dd></div><div><dt>Submitted</dt><dd><time dateTime={value.submission.submitted_at}>{new Date(value.submission.submitted_at).toLocaleString()}</time></dd></div><div><dt>Published questionnaire</dt><dd>{typeof value.questionnaire.source_revision === 'number' ? `Revision ${value.questionnaire.source_revision}` : 'Pinned submitted version'}</dd></div></dl>
      <details><summary>Submission and version references</summary><p>Submission: <code>{id}</code></p><p>Published version: <code>{value.questionnaire.id ?? value.submission.questionnaire_version_id}</code></p></details>
    </section>

    <section id={sectionId('answers')} tabIndex={-1} className="care-review-section" aria-labelledby={sectionId('answers-heading')}>
      <div className="professional-row professional-between"><h3 id={sectionId('answers-heading')}>Patient's original submitted answers</h3><span className="professional-badge">Read-only</span></div>
      <p>{value.questionnaire.content.questions.length} questions in the pinned published version. Responses and picture selections below are the patient's original submission.</p>
      <label className="professional-label">Answer language<select className="neo-input" value={locale} onChange={event => setLocale(event.target.value as Locale)}>{value.questionnaire.content.locales.map(language => <option value={language} key={language}>{localeNames[language]}</option>)}</select></label>
      <QuestionFields questions={value.questionnaire.content.questions} answers={value.submission.answers} locale={locale} disabled />
      <CareLink href={`#${sectionId('review')}`}>Continue to psychologist review</CareLink>
    </section>

    <section id={sectionId('evaluation')} tabIndex={-1} className="care-review-section" aria-labelledby={sectionId('evaluation-heading')}>
      <h3 id={sectionId('evaluation-heading')}>AI evaluation and evidence</h3><p role="status"><span className="professional-badge">{stateLabel}</span></p>
      <p>{value.job.state === 'queued' ? 'The submission is waiting for processing. Refresh to check for an update.' : value.job.state === 'claimed' ? 'Processing has started. An interpretation may not be available yet.' : value.job.state === 'failed' ? 'Processing failed. No completed interpretation is implied.' : 'Inspect the available interpretation and supporting evidence before recording your own review.'}</p>
      <p className="care-review-message">A pending or unavailable AI evaluation does not prevent manual review of the original answers. Enter your own conclusion below to use the existing review actions.</p>
      <div className="professional-grid"><section className="professional-question"><h4>Available interpretation</h4><p dir="auto" className="care-review-prose">{value.evaluation.interpretation ?? 'No AI interpretation is available. You can review the original answers manually.'}</p></section>
        <section className="professional-question"><h4>Supporting evidence</h4>{value.evaluation.evidence.length ? <ul className="professional-stack">{value.evaluation.evidence.map((reference, index) => {
          const position = value.questionnaire.content.questions.findIndex(question => question.id === reference.question_id), question = value.questionnaire.content.questions[position];
          return <li key={index}><strong>{position >= 0 ? `Question ${position + 1}` : 'Question reference'}</strong>{question && <p dir={locale === 'ur' ? 'rtl' : 'auto'}>{question.prompt[locale]}</p>}<p className="professional-muted">Question ID: <code>{reference.question_id}</code>; answer reference {reference.answer_index + 1}</p></li>;
        })}</ul> : <p>No evidence references are available for this evaluation.</p>}</section></div>
      {value.evaluation.validated_scores.length ? <details><summary>Available validated scores</summary><ul>{value.evaluation.validated_scores.map(score => <li key={score.scale_id}>{score.scale_id}: {score.value}; scoring {score.scoring_version}; implementation {score.implementation_version}</li>)}</ul></details> : <p className="professional-muted">No validated scores are available for this submission.</p>}
      <details><summary>Technical evaluation details</summary><p>Job state: <code>{value.job.state}</code></p>{value.job.failure_code && <p>Failure code: <code>{value.job.failure_code}</code></p>}</details>
    </section>

    <section id={sectionId('review')} tabIndex={-1} className="care-review-section" aria-labelledby={sectionId('review-heading')}>
      <h3 id={sectionId('review-heading')}>Psychologist review</h3><p>Your decision, conclusion and optional feedback are saved as a new immutable review revision. The original evaluation is preserved, and this review stays in the professional workspace.</p>
      <p id={sectionId('requirements')} className="care-review-message">{busy ? 'Saving your review. Review actions are temporarily disabled.' : !conclusion.trim() ? 'Enter a psychologist conclusion to enable Approve, Reject and Save Feedback. Feedback is optional; a conclusion is required for every action.' : 'Your conclusion is entered. Choose the review action you intend to record.'}</p>
      <label className="professional-label">Psychologist conclusion (required)<textarea className="neo-input" aria-label="Psychologist conclusion" aria-describedby={sectionId('requirements')} required value={conclusion} maxLength={16000} rows={6} dir="auto" disabled={busy} onChange={event => setConclusion(event.target.value)} /></label>
      <label className="professional-label">Feedback (optional)<textarea className="neo-input" aria-label="Review feedback" value={feedback} maxLength={4000} rows={3} dir="auto" disabled={busy} onChange={event => setFeedback(event.target.value)} /></label>
      <div className="professional-row">{(['approve', 'reject', 'feedback'] as const).map(action => <NeoButton key={action} variant={action === 'reject' ? 'danger' : action === 'feedback' ? 'secondary' : 'primary'} disabled={busy || !conclusion.trim()} aria-describedby={sectionId('requirements')} onClick={() => void decide(action)}>{action === 'approve' ? 'Approve review' : action === 'reject' ? 'Reject evaluation' : 'Save feedback'}</NeoButton>)}</div>
      <div role="status" aria-live="polite">{message && <p className="care-review-message">{message}</p>}</div>
      {reviewError && <p role="alert" className="professional-error">{reviewError}</p>}
    </section>

    <section id={sectionId('history')} tabIndex={-1} className="care-review-section" aria-labelledby={sectionId('history-heading')}>
      <h3 id={sectionId('history-heading')}>Previous review history</h3><p>Saved revisions never overwrite an earlier review. Open a revision to read its complete conclusion and feedback.</p>
      {historyState === 'loading' && <p role="status">Loading review revisions...</p>}
      {historyState === 'error' && <p role="alert" className="professional-error">Review history could not be refreshed. Previously loaded revisions are retained.</p>}
      {historyState === 'ready' && !history.length && <p>No review revisions yet.</p>}
      {history.slice().sort((a, b) => b.review.revision - a.review.revision).map(row => <details className="care-history-entry" key={row.review.id}><summary>Revision {row.review.revision}: {decisionNames[row.decision]} - {new Date(row.review.created_at).toLocaleString()}</summary><div className="professional-stack"><h4>Psychologist conclusion</h4><p dir="auto" className="care-review-prose">{row.review.conclusion}</p>{row.review.feedback && <><h4>Feedback</h4><p dir="auto" className="care-review-prose">{row.review.feedback}</p></>}<p className="professional-muted">Reviewer: <bdi>{row.review.reviewer_uid}</bdi> | Decision: <code>{row.decision}</code></p></div></details>)}
      <div className="professional-row">{cursor && <NeoButton variant="ghost" disabled={busy || historyState === 'loading'} onClick={() => void historyPage(value.evaluation.id, cursor).catch(onError)}>More review revisions</NeoButton>}<NeoButton variant="ghost" disabled={busy} onClick={() => void load().catch(loadFailure)}>Refresh evaluation and reviews</NeoButton><CareLink href={`#${sectionId('overview')}`}>Back to submission overview</CareLink></div>
    </section>
  </NeoCard>;
}
