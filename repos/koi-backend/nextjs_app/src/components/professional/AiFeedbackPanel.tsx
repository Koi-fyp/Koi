'use client';
import { useId, useState } from 'react';
import NeoButton from '@/components/ui/NeoButton';
import { ACTION_FAILED, useSnackbar } from '@/components/ui/feedback';
import type { ProfessionalApi } from '@/lib/platform/client';
import { AI_FEEDBACK_COMMENT_MAX, AI_FEEDBACK_TAGS, type AiFeedbackNote, type AiFeedbackTag } from '@/lib/platform/ai-feedback';

// Evaluations rated in this browser session; the server keeps only the first note anyway.
const sentThisSession = new Set<string>();
export const resetAiFeedbackSession = () => sentThisSession.clear();

export default function AiFeedbackPanel({ api, evaluationId, onError }: { api: ProfessionalApi; evaluationId: string; onError: (e: unknown) => void }) {
  const id = useId(), snackbar = useSnackbar();
  const [rating, setRating] = useState(0), [tags, setTags] = useState<AiFeedbackTag[]>([]), [comment, setComment] = useState('');
  const [busy, setBusy] = useState(false), [sent, setSent] = useState(() => sentThisSession.has(evaluationId)), [error, setError] = useState('');
  const length = Array.from(comment).length;
  const send = async () => {
    if (busy || sent || !rating || length > AI_FEEDBACK_COMMENT_MAX) return;
    setBusy(true); setError('');
    try {
      await api.request<AiFeedbackNote>(`/api/v1/professional/evaluations/${encodeURIComponent(evaluationId)}/ai-feedback`, 'POST', { rating, tags, ...(comment.trim() ? { comment: comment.trim() } : {}) });
      sentThisSession.add(evaluationId); setSent(true); snackbar.success('Sent');
    } catch (e) { setError('Feedback was not recorded. Retry when connected; a retry never creates a second note.'); snackbar.error(ACTION_FAILED); onError(e); }
    finally { setBusy(false); }
  };
  return <section className="professional-question care-ai-feedback" aria-labelledby={`${id}-title`}>
    <h4 id={`${id}-title`}>Rate this AI analysis</h4>
    <p className="professional-muted">Private to your practice. It helps improve AI drafts and is never shown to patients.</p>
    {sent ? <p role="status" className="care-review-message">Thanks, feedback recorded</p> : null}
    <fieldset disabled={sent || busy} className="professional-stack" style={{ border: 0, padding: 0, minWidth: 0 }}>
      <div role="radiogroup" aria-label="Rating from 1 (poor) to 5 (excellent)" className="professional-row">{[1, 2, 3, 4, 5].map(value => <label key={value} className="care-rating"><input type="radio" name={`${id}-rating`} value={value} checked={rating === value} onChange={() => setRating(value)} />{value}</label>)}</div>
      <div role="group" aria-label="What describes this analysis?" className="professional-row">{AI_FEEDBACK_TAGS.map(tag => <label key={tag} className="care-chip"><input type="checkbox" checked={tags.includes(tag)} onChange={e => setTags(old => e.target.checked ? [...old, tag] : old.filter(t => t !== tag))} /> {tag}</label>)}</div>
      <label className="professional-label">Comment (optional)<textarea className="neo-input" aria-label="AI feedback comment" aria-describedby={`${id}-count`} rows={3} value={comment} onChange={e => setComment(e.target.value)} /></label>
      <p id={`${id}-count`} className={length > AI_FEEDBACK_COMMENT_MAX ? 'professional-error' : 'professional-muted'}>{length} / {AI_FEEDBACK_COMMENT_MAX} characters</p>
      <NeoButton variant="secondary" disabled={!rating || length > AI_FEEDBACK_COMMENT_MAX} onClick={() => void send()}>Send feedback</NeoButton>
    </fieldset>
    {error && <p role="alert" className="professional-error">{error}</p>}
  </section>;
}
