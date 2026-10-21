'use client';
import { useEffect, useRef, useState } from 'react';
import NeoButton from '@/components/ui/NeoButton';
import NeoCard from '@/components/ui/NeoCard';
import NeoInput from '@/components/ui/NeoInput';
import { PlatformClientError, type ProfessionalApi } from '@/lib/platform/client';
import type { ManualContent } from '@/lib/platform/types';

export interface AiProvenance { provider: string; model_id: string; prompt_version: string; sources: string[] }
interface AiDraftResult { content: ManualContent; provenance: AiProvenance; notice: string }
type Failure = 'not_configured' | 'rate_limited' | 'provider' | 'unavailable' | 'rejected' | 'denied';
const messages: Record<Failure, string> = {
  not_configured: 'AI drafting is not configured on this server yet.',
  rate_limited: 'The AI service is busy or your limit was reached. Wait a minute, then try again.',
  provider: 'The AI service could not produce a usable draft this time. Nothing was saved.',
  unavailable: 'The practice service could not be reached. Nothing was saved.',
  rejected: 'The AI service could not accept this request. Shorten or rephrase the topic and audience, then try again.',
  denied: 'AI drafting is not available for this account.',
};
const languages = [['en', 'English'], ['ur', 'اردو'], ['roman_ur', 'Roman Urdu']] as const;

export default function AiDraftPanel({ api, disabled, onDraft, onManual, onSessionError }: {
  api: ProfessionalApi; disabled: boolean;
  onDraft: (content: ManualContent, provenance: AiProvenance) => void;
  onManual: () => void; onSessionError: (failure: unknown) => void;
}) {
  const [topic, setTopic] = useState(''), [audience, setAudience] = useState('');
  const [language, setLanguage] = useState<'en' | 'ur' | 'roman_ur'>('en'), [count, setCount] = useState(8);
  const [working, setWorking] = useState(false), [failure, setFailure] = useState<Failure | null>(null);
  const alive = useRef(true);
  useEffect(() => { alive.current = true; return () => { alive.current = false; }; }, []);
  const valid = topic.trim().length > 0 && audience.trim().length > 0 && Number.isInteger(count) && count >= 1 && count <= 20;
  const generate = async () => {
    setWorking(true); setFailure(null);
    try {
      const result = await api.request<AiDraftResult>('/api/v1/professional/questionnaire-drafts/ai', 'POST', { topic: topic.trim(), audience: audience.trim(), language, count });
      if (alive.current) onDraft(result.content, result.provenance);
    } catch (error) {
      if (!alive.current) return;
      if (error instanceof PlatformClientError && (error.status === 401 || error.code === 'reauth_cancelled')) { onSessionError(error); return; }
      const status = error instanceof PlatformClientError ? error.status : 503, code = error instanceof PlatformClientError ? error.code : '';
      setFailure(code === 'ai_unavailable' ? 'not_configured' : status === 429 ? 'rate_limited' : status === 502 || code === 'ai_provider_error' ? 'provider'
        : status === 403 ? 'denied' : status === 422 ? 'rejected' : 'unavailable');
    } finally { if (alive.current) setWorking(false); }
  };
  return <NeoCard className="professional-card" aria-label="Draft with AI">
    <h2>Draft with AI</h2>
    <p className="professional-muted">The AI proposes a first draft only. It loads here unsaved, and you review every question before saving or publishing.</p>
    <form className="professional-stack" onSubmit={event => { event.preventDefault(); if (valid && !working) void generate(); }}>
      <NeoInput label="AI topic" aria-label="AI topic" value={topic} maxLength={200} disabled={disabled || working} onChange={event => setTopic(event.target.value)} />
      <NeoInput label="AI audience" aria-label="AI audience" value={audience} maxLength={200} disabled={disabled || working} onChange={event => setAudience(event.target.value)} />
      <div className="professional-row">
        <label className="professional-label">AI language<select className="neo-input" value={language} disabled={disabled || working} onChange={event => setLanguage(event.target.value as typeof language)}>{languages.map(([value, name]) => <option value={value} key={value}>{name}</option>)}</select></label>
        <NeoInput type="number" label="Number of questions" aria-label="Number of questions" min={1} max={20} value={count} disabled={disabled || working} onChange={event => setCount(Number(event.target.value))} />
      </div>
      <div className="professional-row"><NeoButton type="submit" loading={working} disabled={disabled || working || !valid}>Generate draft</NeoButton></div>
    </form>
    {working && <div className="professional-status" role="status" aria-live="polite"><span className="neo-spinner" aria-hidden="true" />Generating your draft. This can take up to 60 seconds.</div>}
    {failure && <div role="alert" className="professional-error"><p>{messages[failure]}</p><NeoButton type="button" variant="secondary" disabled={disabled} onClick={() => { setFailure(null); onManual(); }}>Build manually instead</NeoButton></div>}
  </NeoCard>;
}

/** Shown above the editor while the loaded questionnaire is still an AI draft. */
export function AiReviewBanner({ provenance, saved, busy, onConfirm }: { provenance: AiProvenance | null; saved: boolean; busy: boolean; onConfirm: () => void }) {
  return <section className="professional-card" aria-label="AI draft notice">
    <p role="note"><strong>AI draft, not validated: review every question before saving.</strong></p>
    {provenance && <p className="professional-muted">Provider: {provenance.provider} · Model: {provenance.model_id} · Prompt version: {provenance.prompt_version} · Sources: {provenance.sources.length ? provenance.sources.join('; ') : 'none listed'}</p>}
    <label className="professional-row"><input type="checkbox" checked={false} disabled={busy || !saved} onChange={event => { if (event.target.checked) onConfirm(); }} />I reviewed this draft</label>
    <p className="professional-muted">{saved ? 'Ticking this records your review on the server. Until then the draft can be saved but cannot be published.' : 'Save the draft first, then confirm your review. Until you confirm, it can be saved but cannot be published.'}</p>
  </section>;
}
