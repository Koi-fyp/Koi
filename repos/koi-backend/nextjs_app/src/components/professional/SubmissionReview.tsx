'use client';
import { useEffect, useRef, useState } from 'react';
import NeoButton from '@/components/ui/NeoButton';
import NeoCard from '@/components/ui/NeoCard';
import type { ProfessionalApi } from '@/lib/platform/client';
import type { Decision, ReviewDecision, SubmissionWorkspace } from '@/lib/platform/professional-types';
import type { Page } from '@/lib/platform/patient-types';
import type { Locale } from '@/lib/platform/types';
import QuestionFields from '@/components/patient/QuestionFields';
export default function SubmissionReview({ id, api, onError }: { id: string; api: ProfessionalApi; onError: (error: unknown) => void }) {
  const [value, setValue] = useState<SubmissionWorkspace | null>(null), [history, setHistory] = useState<Decision[]>([]), [cursor, setCursor] = useState<string | null>(null);
  const [conclusion, setConclusion] = useState(''), [feedback, setFeedback] = useState(''), [busy, setBusy] = useState(false), [message, setMessage] = useState(''), [locale, setLocale] = useState<Locale>('en');
  const alive = useRef(true), running = useRef(false);
  const historyPage = async (eid: string, next?: string) => {
    const result = await api.request<Page<Decision>>(`/api/v1/professional/evaluations/${eid}/review-decisions${next ? `?cursor=${encodeURIComponent(next)}` : ''}`);
    if (alive.current) { setHistory(old => next ? [...old, ...result.items] : result.items); setCursor(result.next_cursor); }
  };
  const load = async () => {
    const result = await api.request<SubmissionWorkspace>(`/api/v1/professional/submissions/${id}/workspace`);
    if (!alive.current) return; setValue(result); setLocale(result.questionnaire.content.locales[0]); await historyPage(result.evaluation.id);
  };
  useEffect(() => { alive.current = true; void load().catch(onError); return () => { alive.current = false; }; }, [id, api]);
  if (!value) return <p role="status"><span className="neo-spinner" aria-hidden="true" />Loading protected submission…</p>;
  const decide = async (decision: ReviewDecision) => {
    if (running.current || !conclusion.trim()) return;
    if (!window.confirm(`Save this ${decision} decision as an immutable review revision?`)) return;
    running.current = true; setBusy(true); setMessage('');
    try {
      await api.request('/api/v1/professional/review-decisions', 'POST', { organization_id: value.submission.organization_id, evaluation_id: value.evaluation.id, expected_review_revision: value.review_revision, conclusion, ...(feedback.trim() ? { feedback } : {}), decision });
      if (alive.current) { setConclusion(''); setFeedback(''); setMessage('Review revision saved. Original interpretation preserved.'); await load(); }
    } catch (e) { onError(e); }
    finally { running.current = false; if (alive.current) setBusy(false); }
  };
  return <NeoCard className="professional-card" aria-label="Protected submission review" aria-busy={busy}>
    <h2>Submission and clinician review</h2><p>Patient: {value.submission.patient_uid} · Submitted {new Date(value.submission.submitted_at).toLocaleString()}</p>
    <label>Answer language <select className="neo-input" value={locale} onChange={e => setLocale(e.target.value as Locale)}>{value.questionnaire.content.locales.map(l => <option key={l}>{l}</option>)}</select></label>
    <QuestionFields questions={value.questionnaire.content.questions} answers={value.submission.answers} locale={locale} disabled />
    <div className="professional-grid"><section className="professional-question"><h3>Original evaluation</h3><p>AI processing: {value.job.state === 'queued' ? 'Pending — evaluation worker is not connected in this slice.' : value.job.state === 'failed' ? `Unavailable (${value.job.failure_code ?? 'provider_unavailable'})` : value.job.state}</p>
      {value.evaluation.validated_scores.length ? <ul>{value.evaluation.validated_scores.map(score => <li key={score.scale_id}>{score.scale_id}: {score.value} · Scoring {score.scoring_version} · Implementation {score.implementation_version}</li>)}</ul> : <p>No validated deterministic score applies to this custom questionnaire.</p>}
      <p style={{ whiteSpace: 'pre-wrap' }}>{value.evaluation.interpretation ?? 'No AI interpretation is available. You can review the original answers manually.'}</p>
      {value.evaluation.evidence.length > 0 && <ul>{value.evaluation.evidence.map((ref, i) => <li key={i}>Question {ref.question_id}, answer {ref.answer_index + 1}</li>)}</ul>}
    </section><section className="professional-question"><h3>Your review</h3><p>Saved revisions never replace the original evaluation. This review stays in the professional workspace.</p>
      <label className="professional-label">Psychologist conclusion<textarea className="neo-input" aria-label="Psychologist conclusion" value={conclusion} maxLength={16000} rows={5} disabled={busy} onChange={e => setConclusion(e.target.value)} /></label>
      <label className="professional-label">Feedback<textarea className="neo-input" aria-label="Review feedback" value={feedback} maxLength={4000} rows={3} disabled={busy} onChange={e => setFeedback(e.target.value)} /></label>
      <div className="professional-row">{(['approve', 'reject', 'feedback'] as const).map(action => <NeoButton key={action} disabled={busy || !conclusion.trim()} onClick={() => void decide(action)}>{action === 'approve' ? 'Approve review' : action === 'reject' ? 'Reject evaluation' : 'Save feedback'}</NeoButton>)}</div>
    </section></div><p role="status">{message}</p><h3>Append-only review history</h3>{!history.length && <p>No review revisions yet.</p>}{history.slice().sort((a, b) => b.review.revision - a.review.revision).map(row => <article className="professional-question" key={row.review.id}><strong>Revision {row.review.revision} · {row.decision}</strong><p style={{ whiteSpace: 'pre-wrap' }}>{row.review.conclusion}</p>{row.review.feedback && <p>{row.review.feedback}</p>}<small>{row.review.reviewer_uid} · {row.review.created_at}</small></article>)}
    {cursor && <NeoButton onClick={() => void historyPage(value.evaluation.id, cursor).catch(onError)}>More review revisions</NeoButton>}<NeoButton variant="ghost" onClick={() => void load().catch(onError)}>Refresh evaluation and reviews</NeoButton>
  </NeoCard>;
}
