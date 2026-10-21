'use client';
import { useEffect, useRef, useState } from 'react';
import NeoButton from '@/components/ui/NeoButton';
import NeoCard from '@/components/ui/NeoCard';
import NeoInput from '@/components/ui/NeoInput';
import { browserContentHash, canonicalJson } from '@/lib/platform/canonical';
import { contentIssues, emptyContent } from '@/lib/platform/content';
import { PlatformClientError, type ProfessionalApi } from '@/lib/platform/client';
import type { CapabilitiesDTO, DraftDTO, DraftListDTO, ManualContent, OrganizationDTO, VersionDTO } from '@/lib/platform/types';
import QuestionnaireEditor from './QuestionnaireEditor';
import AiDraftPanel, { AiReviewBanner, type AiProvenance } from './AiDraftPanel';
import PublishedQuestionnaire from './PublishedQuestionnaire';
import PatientManagement from './PatientManagement';
import MessagesScreen from '@/components/messaging/MessagesScreen';

export function WorkspaceLoading({ text = 'Loading your workspace…' }: { text?: string }) {
  return <div className="professional-status" role="status" aria-live="polite"><span className="neo-spinner" aria-hidden="true" />{text}</div>;
}
export default function ProfessionalWorkspace({ api, onSessionExpired }: { api: ProfessionalApi; onSessionExpired: () => void }) {
  const [phase, setPhase] = useState<'loading' | 'ready' | 'denied' | 'unavailable'>('loading');
  const [org, setOrg] = useState<string | null>(null), [orgName, setOrgName] = useState('');
  const [organizationName, setOrganizationName] = useState('');
  const [items, setItems] = useState<DraftDTO[]>([]), [cursor, setCursor] = useState<string | null>(null);
  const [draft, setDraft] = useState<DraftDTO | null>(null), [content, setContent] = useState<ManualContent | null>(null);
  const [version, setVersion] = useState<VersionDTO | null>(null), [inspectRevision, setInspectRevision] = useState(1);
  const [busy, setBusy] = useState(false), [message, setMessage] = useState(''), [error, setError] = useState('');
  const [issues, setIssues] = useState<string[]>([]), [aiInfo, setAiInfo] = useState<AiProvenance | null>(null);
  const [showPatients, setShowPatients] = useState(false), [messagesView, setMessagesView] = useState(false);
  useEffect(() => { const view = new URLSearchParams(window.location.search).get('view'); setMessagesView(view === 'messages'); if (view && view !== 'questionnaires' && view !== 'messages') setShowPatients(true); }, []);
  const busyRef = useRef(false), alive = useRef(true);
  const clearProtected = () => { setContent(null); setDraft(null); setVersion(null); setItems([]); setOrg(null); setCursor(null); };
  const handleError = (failure: unknown) => {
    if (!alive.current) return;
    if (failure instanceof PlatformClientError && failure.status === 401) { clearProtected(); onSessionExpired(); return; }
    if (failure instanceof PlatformClientError && failure.status === 403) { clearProtected(); setPhase('denied'); return; }
    if (failure instanceof PlatformClientError && failure.code === 'reauth_cancelled') setError('Sign-in was cancelled. Your unsaved edits are still here.');
    else if (failure instanceof PlatformClientError && failure.status === 409) setError('This draft changed, or this request conflicts with a previous action. Your edits are still here. Reload the saved draft before trying again.');
    else if (failure instanceof PlatformClientError && failure.status === 422) setError('Check the question text, options, languages and picture selections, then try again. The draft must fit the supported size limits.');
    else if (failure instanceof PlatformClientError && failure.status === 404) setError('This item or published revision is unavailable.');
    else setError('The workspace is unavailable. Retry when your connection or practice service is ready. Your saved drafts stay unchanged.');
  };
  const loadList = async (organization: string, next?: string) => {
    const page = await api.request<DraftListDTO>(`/api/v1/professional/questionnaires?organization_id=${encodeURIComponent(organization)}${next ? `&cursor=${encodeURIComponent(next)}` : ''}`);
    if (!alive.current) return;
    setItems(old => next ? [...old, ...page.items.filter(item => !old.some(existing => existing.id === item.id))] : page.items); setCursor(page.next_cursor);
  };
  const access = async (initial = false) => {
    try {
      const caps = await api.request<CapabilitiesDTO>('/api/v1/me/capabilities');
      if (!alive.current) return;
      if (!caps.capabilities.professional_workspace) { clearProtected(); setPhase('denied'); return; }
      const organization = caps.professional_organization_ids[0] ?? null;
      setOrg(organization); setPhase('ready');
      if (initial && organization) await loadList(organization);
      if (initial) {
        const id = new URLSearchParams(window.location.search).get('version');
        if (id) {
          const snapshot = await api.request<VersionDTO>(`/api/v1/professional/questionnaire-versions/${encodeURIComponent(id)}`);
          if (alive.current) setVersion(snapshot);
        }
      }
    } catch (failure) {
      if (!alive.current) return;
      handleError(failure);
      if (!(failure instanceof PlatformClientError && [401, 403].includes(failure.status))) setPhase('unavailable');
    }
  };
  useEffect(() => {
    alive.current = true; void access(true);
    const refresh = () => { if (!busyRef.current) void access(); };
    window.addEventListener('focus', refresh);
    return () => { alive.current = false; window.removeEventListener('focus', refresh); };
  }, [api]); // API and all protected state are discarded with this signed-in session.
  const run = async (action: () => Promise<void>) => {
    if (busyRef.current) return;
    busyRef.current = true; setBusy(true); setError(''); setMessage('');
    try { await action(); } catch (failure) { handleError(failure); }
    finally { busyRef.current = false; if (alive.current) setBusy(false); }
  };
  const dirty = !!content && (!draft || canonicalJson(content) !== canonicalJson(draft.content));
  const discard = () => !dirty || window.confirm('Discard your unsaved edits?');
  const openDraft = async (id: string) => {
    const saved = await api.request<DraftDTO>(`/api/v1/professional/questionnaires/${encodeURIComponent(id)}`);
    if (!alive.current) return;
    setDraft(saved); setContent(saved.content); setVersion(null); setIssues([]); setInspectRevision(saved.revision); setAiInfo(null);
  };
  const loadAiDraft = (next: ManualContent, provenance: AiProvenance) => {
    if (!discard()) return;
    setDraft(null); setContent(next); setAiInfo(provenance); setVersion(null); setIssues([]); setError(''); setMessage('AI draft loaded. It is not saved yet.');
  };
  const buildManually = () => { if (discard()) { setDraft(null); setContent(emptyContent()); setAiInfo(null); setVersion(null); setIssues([]); setError(''); setMessage(''); } };
  const confirmReview = () => run(async () => {
    if (!draft || dirty) return;
    const saved = await api.request<DraftDTO>(`/api/v1/professional/questionnaires/${draft.id}/confirm-review`, 'POST', { expected_revision: draft.revision });
    if (!alive.current) return;
    setDraft(saved); setContent(saved.content); setInspectRevision(saved.revision); setAiInfo(null); setMessage(`Review confirmed. Revision ${saved.revision} can now be published.`); if (org) await loadList(org);
  });
  const save = () => run(async () => {
    if (!content || !org) return;
    const found = contentIssues(content); setIssues(found);
    if (found.length) return;
    const saved = await api.request<DraftDTO>(draft ? `/api/v1/professional/questionnaires/${draft.id}` : '/api/v1/professional/questionnaires', draft ? 'PUT' : 'POST', draft ? { expected_revision: draft.revision, content } : { organization_id: org, content });
    if (!alive.current) return;
    setDraft(saved); setContent(saved.content); setInspectRevision(saved.revision); setMessage(`Draft saved. Revision ${saved.revision}.`); await loadList(org);
  });
  if (phase === 'loading') return <WorkspaceLoading />;
  if (phase === 'denied') return <NeoCard className="professional-card"><h1>Practice access required</h1><p>This workspace is available to approved psychologists with an active practice membership. A general or anonymous KOI session does not grant access.</p><NeoButton onClick={() => void access(true)}>Check access again</NeoButton></NeoCard>;
  if (phase === 'unavailable') return <NeoCard className="professional-card"><h1>Workspace unavailable</h1><p role="alert">The practice service is not ready or could not be reached. No example practice or saved form has been substituted.</p><NeoButton onClick={() => { setPhase('loading'); void access(true); }}>Retry workspace</NeoButton></NeoCard>;
  return <>
    <div className="professional-row professional-between"><div><h1>{orgName || 'Your practice'}</h1><p className="professional-muted">Create, save and publish your own questionnaires.</p></div><span className="professional-badge">Custom · Not validated</span></div>
    {error && <p role="alert" className="professional-error">{error}</p>}
    {messagesView && <section id="messages"><MessagesScreen api={api} role="professional" organizationId={org} onError={handleError} /></section>}
    <div role="status" aria-live="polite">{busy ? <span className="professional-row"><span className="neo-spinner" aria-hidden="true" />Saving or loading…</span> : message}</div>
    {!org ? <NeoCard className="professional-card professional-narrow"><h2>Create your organization</h2><p className="professional-muted">Your organization holds your drafts and published versions.</p>
      <form className="professional-stack" onSubmit={event => { event.preventDefault(); void run(async () => {
        const result = await api.request<OrganizationDTO>('/api/v1/professional/organizations', 'POST', { name: organizationName });
        if (!alive.current) return;
        setOrg(result.id); setOrgName(result.name); setMessage('Organization created.'); await loadList(result.id);
      }); }}><NeoInput label="Organization name" aria-label="Organization name" value={organizationName} maxLength={160} required disabled={busy} onChange={event => setOrganizationName(event.target.value)} /><NeoButton type="submit" loading={busy} disabled={!organizationName.trim()}>Create organization</NeoButton></form>
    </NeoCard> : <>
      <NeoCard className="professional-card"><div className="professional-row professional-between"><h2 id="professional-questionnaires">Your questionnaires</h2><NeoButton disabled={busy} onClick={() => { if (discard()) { setDraft(null); setContent(emptyContent()); setAiInfo(null); setVersion(null); setIssues([]); setError(''); setMessage(''); } }}>New questionnaire</NeoButton></div>
        {!items.length && <p className="professional-muted">No saved drafts yet. Create your first manual questionnaire.</p>}
        <ul className="professional-stack">{items.map(item => <li key={item.id} className="professional-row professional-between"><div><strong>{item.content.title[item.content.locales[0]]}</strong><p className="professional-muted">Draft revision {item.revision}</p></div><NeoButton variant="ghost" disabled={busy} onClick={() => { if (discard()) void run(() => openDraft(item.id)); }}>Open draft: {item.content.title[item.content.locales[0]]}</NeoButton></li>)}</ul>
        {cursor && <NeoButton variant="ghost" disabled={busy} onClick={() => void run(() => loadList(org, cursor))}>Load more questionnaires</NeoButton>}
      </NeoCard>
      <AiDraftPanel api={api} disabled={busy} onDraft={loadAiDraft} onManual={buildManually} onSessionError={handleError} />
      {content && <NeoCard className="professional-card" aria-busy={busy}><div className="professional-row professional-between"><h2>{draft ? `Edit draft · Revision ${draft.revision}` : content.origin === 'ai_drafted' ? 'New AI-assisted draft' : 'New manual questionnaire'}</h2><span className="professional-muted">{dirty ? 'Unsaved changes' : 'Saved'}</span></div>
        {content.origin === 'ai_drafted' && <AiReviewBanner provenance={aiInfo} saved={!!draft && !dirty} busy={busy} onConfirm={() => void confirmReview()} />}
        <p className="professional-muted">Fill in every selected language before saving. Published versions always keep their original questions and pictures.</p>
        {issues.length > 0 && <ul role="alert" className="professional-error">{issues.map((issue, i) => <li key={i}>{issue}</li>)}</ul>}
        <QuestionnaireEditor content={content} disabled={busy} onChange={next => { setContent(next); setIssues([]); }} />
        <div className="professional-row"><NeoButton disabled={busy || !dirty} onClick={save}>Save draft</NeoButton>
          {draft && <><NeoButton variant="secondary" disabled={busy || dirty || content.origin === 'ai_drafted'} onClick={() => {
            if (!window.confirm('Publish this saved revision? Its published version cannot be edited.')) return;
            void run(async () => {
              const result = await api.request<VersionDTO>(`/api/v1/professional/questionnaires/${draft.id}/publish`, 'POST', { expected_revision: draft.revision, expected_content_sha256: await browserContentHash(draft.content) });
              if (alive.current) { setVersion(result); setInspectRevision(result.source_revision); setMessage('Published. This version is immutable.'); }
            });
          }}>Publish saved revision</NeoButton><NeoButton variant="ghost" disabled={busy} onClick={() => { if (discard()) void run(() => openDraft(draft.id)); }}>Reload saved draft</NeoButton></>}
        </div>
        {draft && <div className="professional-row"><NeoInput label="Published revision to inspect" aria-label="Published revision to inspect" type="number" min={1} max={draft.revision} value={inspectRevision} disabled={busy} onChange={event => setInspectRevision(Number(event.target.value))} />
          <NeoButton variant="ghost" disabled={busy || !Number.isInteger(inspectRevision) || inspectRevision < 1 || inspectRevision > draft.revision} onClick={() => void run(async () => {
            const id = `version_${await browserContentHash([draft.organization_id, draft.id, inspectRevision])}`;
            const result = await api.request<VersionDTO>(`/api/v1/professional/questionnaire-versions/${id}`);
            if (alive.current) setVersion(result);
          })}>Inspect published revision</NeoButton></div>}
      </NeoCard>}
    </>}
    {version && <PublishedQuestionnaire key={version.id} version={version} />}
    {org && <><NeoButton variant="secondary" onClick={() => setShowPatients(value => !value)}>{showPatients ? 'Hide patients and submissions' : 'Manage patients and submissions'}</NeoButton>{showPatients && <PatientManagement key={org} api={api} organizationId={org} publishedVersionId={version?.id} onDenied={handleError} />}</>}
  </>;
}
