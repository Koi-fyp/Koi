'use client';
import { useEffect, useRef, useState } from 'react';
import NeoButton from '@/components/ui/NeoButton';
import NeoCard from '@/components/ui/NeoCard';
import { PlatformClientError, type ProfessionalApi } from '@/lib/platform/client';
import type { Answer, PatientDetail, SubmitAck } from '@/lib/platform/patient-types';
import type { Locale } from '@/lib/platform/types';
import { answerIssues } from '@/lib/platform/answers';
import QuestionFields from './QuestionFields';
type OpenDetail = Extract<PatientDetail, { attempt: unknown }>;
export default function QuestionnaireRunner({ initial, api, onClose, onDenied, paused = false }: { initial: OpenDetail; api: ProfessionalApi; paused?: boolean; onClose: () => void; onDenied: () => void }) {
  const [answers, setAnswers] = useState(initial.attempt.answers), [locale, setLocale] = useState<Locale>(initial.questionnaire.locales[0]);
  const [saved, setSaved] = useState(JSON.stringify(initial.attempt.answers)), [revision, setRevision] = useState(initial.attempt.revision);
  const [busy, setBusy] = useState(false), [review, setReview] = useState(false), [conflict, setConflict] = useState(false), [error, setError] = useState(''), [ack, setAck] = useState<SubmitAck | null>(null);
  const [remote, setRemote] = useState<OpenDetail | null>(null);
  const alive = useRef(true), inFlight = useRef(false), current = useRef(answers); current.current = answers;
  useEffect(() => { alive.current = true; return () => { alive.current = false; current.current = []; }; }, []);
  const apiRef = useRef(api), pausedRef = useRef(paused), operation = useRef(0);
  apiRef.current = api; pausedRef.current = paused;
  const active = () => alive.current && apiRef.current === api && !pausedRef.current;
  useEffect(() => { operation.current++; inFlight.current = false; setBusy(false); }, [api, paused]);
  const denied = (e: unknown) => e instanceof PlatformClientError && [401, 403, 404].includes(e.status);
  const loadRemote = async () => {
    const detail = await api.request<PatientDetail>(`/api/v1/patient/assignments/${initial.assignment.id}`);
    if (!active()) return;
    if ('acknowledgement' in detail) { setAck(detail.acknowledgement); setAnswers([]); setSaved('[]'); setReview(false); setConflict(false); }
    else setRemote(detail);
  };
  const save = async (value = current.current): Promise<boolean> => {
    if (paused || inFlight.current || conflict || ack) return false;
    const stamp = operation.current;
    const valid = () => active() && stamp === operation.current;
    inFlight.current = true; setBusy(true); setError('');
    try {
      const result = await api.request<{ revision: number }>(`/api/v1/patient/attempts/${initial.attempt.id}`, 'PATCH', { expected_revision: revision, answers: value });
      if (!valid()) return false;
      setRevision(result.revision); setSaved(JSON.stringify(value)); return true;
    } catch (e) {
      if (!valid()) return false;
      if (denied(e)) { onDenied(); return false; }
      if (e instanceof PlatformClientError && e.status === 409) { setConflict(true); setReview(false); try { await loadRemote(); } catch { setError('Could not load the latest answers. Retry when connected.'); } }
      else setError('Answers could not be saved. Keep this page open and retry.');
      return false;
    } finally { if (stamp === operation.current) { inFlight.current = false; if (alive.current) setBusy(false); } }
  };
  const dirty = JSON.stringify(answers) !== saved;
  useEffect(() => {
    if (paused || !dirty || busy || conflict || ack || error || review) return;
    const timer = setTimeout(() => void save(), 900); return () => clearTimeout(timer);
  }, [answers, saved, busy, conflict, ack, error, review, paused, api]);
  useEffect(() => {
    if (!dirty) return;
    const warn = (event: BeforeUnloadEvent) => { event.preventDefault(); event.returnValue = ''; };
    window.addEventListener('beforeunload', warn); return () => window.removeEventListener('beforeunload', warn);
  }, [dirty]);
  if (ack) return <NeoCard className="professional-card"><h2>Questionnaire submitted</h2><p>Your responses were received on {new Date(ack.submitted_at).toLocaleString()}.</p><NeoButton onClick={onClose}>Back to assignments</NeoButton></NeoCard>;
  const completed = answers.filter(a => typeof a.value === 'boolean' || (Array.isArray(a.value) ? a.value.length > 0 : a.value.trim().length > 0)).length;
  return <fieldset disabled={paused} style={{ border: 0, padding: 0, minWidth: 0 }}><NeoCard className="professional-card" aria-busy={busy || paused}>
    <div className="professional-row professional-between"><h2 dir={locale === 'ur' ? 'rtl' : 'ltr'}>{initial.questionnaire.title[locale]}</h2><label>Language <select className="neo-input" value={locale} onChange={e => setLocale(e.target.value as Locale)}>{initial.questionnaire.locales.map(l => <option key={l}>{l}</option>)}</select></label></div>
    <p>{completed} of {initial.questionnaire.questions.length} answered</p><progress aria-label="Questionnaire progress" max={initial.questionnaire.questions.length} value={completed} style={{ width: '100%' }} />
    <p role="status" aria-live="polite">{busy ? <><span className="neo-spinner" aria-hidden="true" /> Saving…</> : dirty ? 'Unsaved changes' : 'All answers saved'}</p>
    {error && <p role="alert" className="professional-error">{error}</p>}
    {conflict && <div className="professional-error" role="alert"><h3>Answers changed on another device</h3><p>Your edits are kept here. Load the saved answers, or deliberately replace them with your current edits.</p>
      {remote && <><details><summary>Compare saved answers</summary><QuestionFields questions={remote.questionnaire.questions} answers={remote.attempt.answers} locale={locale} disabled /></details><NeoButton onClick={() => { setAnswers(remote.attempt.answers); setRevision(remote.attempt.revision); setSaved(JSON.stringify(remote.attempt.answers)); setConflict(false); setRemote(null); setError(''); }}>Use saved answers</NeoButton><NeoButton variant="secondary" onClick={() => { if (!window.confirm('Replace the saved answers with your current edits on the next save?')) return; setRevision(remote.attempt.revision); setSaved(JSON.stringify(remote.attempt.answers)); setConflict(false); setRemote(null); setError(''); }}>Keep my edits</NeoButton></>}
      {!remote && <NeoButton onClick={() => void loadRemote().catch(e => denied(e) ? onDenied() : setError('Latest answers unavailable.'))}>Reload latest answers</NeoButton>}
    </div>}
    {review && <div className="professional-badge">Review your answers before submitting</div>}
    <QuestionFields questions={initial.questionnaire.questions} answers={answers} locale={locale} disabled={review || conflict || busy} onChange={setAnswers} />
    <div className="professional-row">
      {!review ? <><NeoButton disabled={busy || conflict || !dirty} onClick={() => void save()}>Save answers</NeoButton><NeoButton variant="secondary" disabled={busy || conflict || dirty} onClick={() => { const issues = answerIssues(initial.questionnaire.questions, answers, true); if (issues.length) setError(issues.join(' ')); else { setReview(true); setError(''); } }}>Review before submitting</NeoButton>
        <NeoButton variant="ghost" disabled={busy || conflict} onClick={async () => { if (!window.confirm('Restart this questionnaire? Your saved answers will be cleared.')) return; if (await save([])) setAnswers([]); }}>Restart questionnaire</NeoButton></>
        : <><p>Submitting locks these answers. You can return to editing before confirming.</p><NeoButton variant="ghost" disabled={busy} onClick={() => setReview(false)}>Return to editing</NeoButton><NeoButton disabled={busy} onClick={async () => {
          if (paused || inFlight.current) return; const stamp = operation.current; const valid = () => active() && stamp === operation.current; inFlight.current = true; setBusy(true); setError('');
          try { const result = await api.request<SubmitAck>(`/api/v1/patient/attempts/${initial.attempt.id}/submit`, 'POST', { expected_revision: revision }); if (valid()) { setAck(result); setAnswers([]); current.current = []; setSaved('[]'); } }
          catch (e) { if (!valid()) return; if (denied(e)) onDenied(); else if (e instanceof PlatformClientError && e.status === 409) { setConflict(true); setReview(false); await loadRemote().catch(() => setError('Reload the latest saved answers.')); } else setError('Submission was not confirmed. Retry; duplicate requests are safe.'); }
          finally { if (stamp === operation.current) { inFlight.current = false; if (alive.current) setBusy(false); } }
        }}>Confirm final submission</NeoButton></>}
      <NeoButton variant="ghost" disabled={busy} onClick={() => { if (!dirty || window.confirm('Leave without saving your latest edits?')) onClose(); }}>Back to assignments</NeoButton>
    </div>
  </NeoCard></fieldset>;
}
