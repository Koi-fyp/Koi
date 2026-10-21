'use client';
import { useEffect, useRef, useState } from 'react';
import NeoButton from '@/components/ui/NeoButton';
import NeoCard from '@/components/ui/NeoCard';
import CareLink from '@/components/platform/CareLink';
import NeoInput from '@/components/ui/NeoInput';
import { browserContentHash, canonicalJson } from '@/lib/platform/canonical';
import { contentIssues, emptyContent } from '@/lib/platform/content';
import { PlatformClientError, type ProfessionalApi } from '@/lib/platform/client';
import type { CapabilitiesDTO, DraftDTO, DraftListDTO, ManualContent, OrganizationDTO, VersionDTO } from '@/lib/platform/types';
import QuestionnaireEditor from './QuestionnaireEditor';
import AiDraftPanel, { AiReviewBanner, type AiProvenance } from './AiDraftPanel';
import PublishedQuestionnaire from './PublishedQuestionnaire';
import PatientManagement from './PatientManagement';
import PracticeOverview from './PracticeOverview';
import type { Relationship } from '@/lib/platform/patient-types';
import { useCareReveal } from '@/components/platform/care-focus';
import WorkspaceFrame, { professionalViews, useWorkspaceView, useWorkspaceSearchParam, navigateWorkspace } from '@/components/platform/WorkspaceFrame';
import MessagesScreen from '@/components/messaging/MessagesScreen';
import CareNotifications from '@/components/patient/CareNotifications';
import { useConfirm, useConfirmedAction } from '@/components/ui/feedback';

export function WorkspaceLoading({ text = 'Loading your workspace…' }: { text?: string }) {
  return <div className="professional-status" role="status" aria-live="polite"><span className="neo-spinner" aria-hidden="true" />{text}</div>;
}
export default function ProfessionalWorkspace({ api, onSessionExpired }: { api: ProfessionalApi; onSessionExpired: () => void }) {
  const [phase, setPhase] = useState<'loading' | 'ready' | 'denied' | 'unavailable'>('loading');
  const [org, setOrg] = useState<string | null>(null), [orgName, setOrgName] = useState('');
  const [organizationName, setOrganizationName] = useState('');
  const [items, setItems] = useState<DraftDTO[]>([]), [cursor, setCursor] = useState<string | null>(null);
  const [draft, setDraft] = useState<DraftDTO | null>(null), [content, setContent] = useState<ManualContent | null>(null);
  const [knownVersions, setKnownVersions] = useState<VersionDTO[]>([]);
  const [version, setVersion] = useState<VersionDTO | null>(null), [inspectRevision, setInspectRevision] = useState(1);
  const [busy, setBusy] = useState(false), [message, setMessage] = useState(''), [error, setError] = useState('');
  const [issues, setIssues] = useState<string[]>([]), [aiInfo, setAiInfo] = useState<AiProvenance | null>(null);
  const view = useWorkspaceView(professionalViews, 'dashboard');
  const requestedRelationship = useWorkspaceSearchParam('relationship'), requestedVersion = useWorkspaceSearchParam('version');
  const [selectedPatient, setSelectedPatient] = useState<Relationship | null>(null);
  const [visitedViews, setVisitedViews] = useState<string[]>([]);
  const [editorReveal, setEditorReveal] = useState(0), [versionReveal, setVersionReveal] = useState(0), [aiReveal, setAiReveal] = useState(0), [aiVisible, setAiVisible] = useState(false);
  useEffect(() => { if (phase === 'ready') setVisitedViews(old => old.includes(view) ? old : [...old, view]); }, [phase, view]);
  useCareReveal('questionnaire-editor', editorReveal || null, view === 'questionnaires' && !!content);
  useCareReveal('published-questionnaire-panel', versionReveal || null, view === 'questionnaires' && !!version);
  useCareReveal('ai-drafting-panel', aiReveal || null, view === 'questionnaires' && aiVisible);

  useEffect(() => { if (version) setKnownVersions(old => old.some(item => item.id === version.id) ? old : [...old, version]); }, [version]);
  const busyRef = useRef(false), alive = useRef(true), confirm = useConfirm(), ask = useConfirmedAction();
  const clearProtected = () => { setContent(null); setDraft(null); setVersion(null); setItems([]); setOrg(null); setCursor(null); setSelectedPatient(null); setVisitedViews([]); setKnownVersions([]); };
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
  useEffect(() => {
    if (!requestedVersion || phase !== 'ready') return;
    let current = true;
    api.request<VersionDTO>(`/api/v1/professional/questionnaire-versions/${encodeURIComponent(requestedVersion)}`).then(snapshot => {
      if (current && alive.current) { setVersion(snapshot); setVersionReveal(n => n + 1); }
    }).catch(failure => { if (current) handleError(failure); });
    return () => { current = false; };
  }, [requestedVersion, api, phase]);
  const run = async (action: () => Promise<void>) => {
    if (busyRef.current) return;
    busyRef.current = true; setBusy(true); setError(''); setMessage('');
    try { await action(); } catch (failure) { handleError(failure); }
    finally { busyRef.current = false; if (alive.current) setBusy(false); }
  };
  const dirty = !!content && (!draft || canonicalJson(content) !== canonicalJson(draft.content));
  useEffect(() => {
    if (!dirty) return;
    const warn = (event: BeforeUnloadEvent) => { event.preventDefault(); event.returnValue = ''; };
    window.addEventListener('beforeunload', warn);
    return () => window.removeEventListener('beforeunload', warn);
  }, [dirty]);
  /** Runs at once when nothing is unsaved; otherwise only after the themed discard confirmation. */
  const discard = (then: () => void) => {
    if (!dirty) { then(); return; }
    void confirm({ title: 'Discard your unsaved edits?', description: 'Changes made since the last save will be lost. Saved drafts stay unchanged.', confirmLabel: 'Discard edits', cancelLabel: 'Keep editing', tone: 'danger' }).then(ok => { if (ok && alive.current) then(); });
  };
  const openDraft = async (id: string) => {
    const saved = await api.request<DraftDTO>(`/api/v1/professional/questionnaires/${encodeURIComponent(id)}`);
    if (!alive.current) return;
    setDraft(saved); setContent(saved.content); setVersion(null); setIssues([]); setInspectRevision(saved.revision); setAiInfo(null); setEditorReveal(n => n + 1);
  };
  const loadAiDraft = (next: ManualContent, provenance: AiProvenance) => discard(() => {
    setDraft(null); setContent(next); setAiInfo(provenance); setVersion(null); setIssues([]); setError(''); setMessage('AI draft loaded. It is not saved yet.'); setEditorReveal(n => n + 1);
  });
  const buildManually = () => discard(() => { setAiVisible(false); setEditorReveal(n => n + 1); setDraft(null); setContent(emptyContent()); setAiInfo(null); setVersion(null); setIssues([]); setError(''); setMessage(''); });
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
  return <WorkspaceFrame base="/professional" views={professionalViews} view={view}>
    {orgName && <p className="professional-badge">{orgName}</p>}
    {error && <p role="alert" className="professional-error">{error}</p>}
    {(view === 'messages' || visitedViews.includes('messages')) && <section id="messages" hidden={view !== 'messages'}><MessagesScreen api={api} role="professional" organizationId={org} active={view === 'messages'} selectedPatient={selectedPatient} selectedRelationshipId={requestedRelationship} onSelectRelationship={id => navigateWorkspace(`/professional?view=messages${id ? `&relationship=${encodeURIComponent(id)}` : ''}#messages`)} onError={handleError} /></section>}
    <div role="status" aria-live="polite">{busy ? <span className="professional-row"><span className="neo-spinner" aria-hidden="true" />Saving or loading…</span> : message}</div>
    {!org ? <NeoCard className="professional-card professional-narrow"><h2>Create your organization</h2><p className="professional-muted">Your organization groups questionnaires, patient relationships and professional reviews. Manage its public profile from Practice overview.</p>
      <form className="professional-stack" onSubmit={event => { event.preventDefault(); void run(async () => {
        const result = await api.request<OrganizationDTO>('/api/v1/professional/organizations', 'POST', { name: organizationName });
        if (!alive.current) return;
        setOrg(result.id); setOrgName(result.name); setMessage('Organization created.'); await loadList(result.id);
      }); }}><NeoInput label="Organization name" aria-label="Organization name" value={organizationName} maxLength={160} required disabled={busy} onChange={event => setOrganizationName(event.target.value)} /><NeoButton type="submit" loading={busy} disabled={!organizationName.trim()}>Create organization</NeoButton></form>
    </NeoCard> : <>
      {view === 'dashboard' && <div className="professional-grid care-shortcuts"><NeoCard className="professional-card"><h2>Build your questionnaire library</h2><p>Create a manual form or review an AI draft, then publish a saved revision.</p><div className="care-link-actions"><CareLink variant="primary" href="/professional?view=questionnaires#professional-questionnaires">Manage questionnaires</CareLink></div></NeoCard><NeoCard className="professional-card"><h2>Follow up with patients</h2><p>Review applications, assign published forms and inspect submitted answers.</p><div className="care-link-actions"><CareLink variant="primary" href="/professional?view=patients#patients">Open patient roster</CareLink><CareLink variant="secondary" href="/professional?view=submissions#submissions">Review submissions</CareLink><CareLink href="/professional?view=analytics#practice-analytics">View assignments and submissions</CareLink></div></NeoCard></div>}
      {(view === 'dashboard' || visitedViews.includes('dashboard')) && <div hidden={view !== 'dashboard'}><PracticeOverview api={api} organizationId={org} view="profile" onError={handleError} /></div>}
      {(view === 'analytics' || visitedViews.includes('analytics')) && <div hidden={view !== 'analytics'}><PracticeOverview api={api} organizationId={org} view="analytics" onError={handleError} /></div>}
      <div hidden={view !== 'questionnaires'} className="professional-stack">
      <NeoCard className="professional-card"><div className="professional-row professional-between"><h2 id="professional-questionnaires">Your questionnaires</h2></div><div className="professional-grid care-authoring-options"><section><h3>Create manually</h3><p className="professional-muted">Write your own questions and choose response types.</p><NeoButton disabled={busy} onClick={buildManually}>Create manually</NeoButton></section><section><h3>Draft with AI</h3><p className="professional-muted">Unvalidated suggestions. Review every question before publishing.</p><NeoButton variant="secondary" disabled={busy} aria-expanded={aiVisible} aria-controls="ai-drafting-panel" onClick={() => { setAiVisible(value => !value); setAiReveal(n => n + 1); }}>Draft with AI</NeoButton></section></div>
        {!items.length && <p className="professional-muted">No saved drafts yet. Create your first manual questionnaire.</p>}
        <ul className="professional-stack">{items.map(item => <li key={item.id} className="professional-row professional-between"><div><strong>{item.content.title[item.content.locales[0]]}</strong><p className="professional-muted">Draft revision {item.revision}</p></div><NeoButton variant="ghost" disabled={busy} onClick={() => discard(() => void run(() => openDraft(item.id)))}>Open draft: {item.content.title[item.content.locales[0]]}</NeoButton></li>)}</ul>
        {cursor && <NeoButton variant="ghost" disabled={busy} onClick={() => void run(() => loadList(org, cursor))}>Load more questionnaires</NeoButton>}
      </NeoCard>
      <div id="ai-drafting-panel" hidden={!aiVisible} tabIndex={-1}><AiDraftPanel api={api} disabled={busy} onDraft={loadAiDraft} onManual={buildManually} onSessionError={handleError} /></div>
      {content && <NeoCard id="questionnaire-editor" tabIndex={-1} className="professional-card" aria-busy={busy}><div className="professional-row professional-between"><h2>{draft ? `Edit draft · Revision ${draft.revision}` : content.origin === 'ai_drafted' ? 'New AI-assisted draft' : 'New manual questionnaire'}</h2><span className="professional-muted">{dirty ? 'Unsaved changes' : 'Saved'}</span></div>
        {content.origin === 'ai_drafted' && <AiReviewBanner provenance={aiInfo} saved={!!draft && !dirty} busy={busy} onConfirm={() => void confirmReview()} />}
        <ol className="care-steps" aria-label="Publication steps"><li>Create manually or draft with AI</li><li>Review and edit every question</li><li>Save draft</li><li>Confirm AI review if required</li><li>Publish saved revision</li></ol>
        <p className="professional-muted">Fill in every selected language before saving. Published versions always keep their original questions and pictures.</p>
        {issues.length > 0 && <ul role="alert" className="professional-error">{issues.map((issue, i) => <li key={i}>{issue}</li>)}</ul>}
        <QuestionnaireEditor content={content} disabled={busy} onChange={next => { setContent(next); setIssues([]); }} />
        <div className="professional-row"><NeoButton disabled={busy || !dirty} onClick={save}>Save draft</NeoButton>
          {draft && <><NeoButton variant="secondary" disabled={busy || dirty || content.origin === 'ai_drafted'} onClick={() => void ask({ title: `Publish revision ${draft.revision}?`, description: 'Its published version cannot be edited. Patients only receive it after you assign it.', confirmLabel: 'Publish revision', success: 'Revision published' }, run, async () => {
              const result = await api.request<VersionDTO>(`/api/v1/professional/questionnaires/${draft.id}/publish`, 'POST', { expected_revision: draft.revision, expected_content_sha256: await browserContentHash(draft.content) });
              if (alive.current) { setVersion(result); setInspectRevision(result.source_revision); setMessage('Published. This version is immutable.'); setVersionReveal(n => n + 1); }
            })}>Publish saved revision</NeoButton><NeoButton variant="ghost" disabled={busy} onClick={() => discard(() => void run(() => openDraft(draft.id)))}>Reload saved draft</NeoButton></>}
        </div>
        {draft && <div className="professional-row"><NeoInput label="Published revision to inspect" aria-label="Published revision to inspect" type="number" min={1} max={draft.revision} value={inspectRevision} disabled={busy} onChange={event => setInspectRevision(Number(event.target.value))} />
          <NeoButton variant="ghost" disabled={busy || !Number.isInteger(inspectRevision) || inspectRevision < 1 || inspectRevision > draft.revision} onClick={() => void run(async () => {
            const id = `version_${await browserContentHash([draft.organization_id, draft.id, inspectRevision])}`;
            const result = await api.request<VersionDTO>(`/api/v1/professional/questionnaire-versions/${id}`);
            if (alive.current) { setVersion(result); setVersionReveal(n => n + 1); }
          })}>Inspect published revision</NeoButton></div>}
      </NeoCard>}
      </div>
    </>}
    {view === 'notifications' && <section id="notifications"><CareNotifications api={api} workspace="professional" onError={handleError} /></section>}
    {view === 'questionnaires' && version &&<div id="published-questionnaire-panel" tabIndex={-1} className="professional-stack"><PublishedQuestionnaire key={version.id} version={version} /><CareLink variant="primary" href="/professional?view=patients#patients">Assign this published version to patients</CareLink></div>}
    {org && (['patients', 'submissions', 'appointments'].includes(view) || visitedViews.some(item => ['patients', 'submissions', 'appointments'].includes(item))) && <div hidden={!['patients', 'submissions', 'appointments'].includes(view)}><PatientManagement key={org} active={['patients', 'submissions', 'appointments'].includes(view)} view={(['patients', 'submissions', 'appointments'].includes(view) ? view : 'patients') as 'patients' | 'submissions' | 'appointments'} api={api} organizationId={org} publishedVersionId={version?.id} knownVersions={knownVersions} selectedRelationshipId={requestedRelationship} onOpenConversation={setSelectedPatient} onDenied={handleError} /></div>}
  </WorkspaceFrame>;
}
