'use client';
import { useEffect, useRef, useState } from 'react';
import NeoButton from '@/components/ui/NeoButton';
import NeoInput from '@/components/ui/NeoInput';
import { PlatformClientError, type ProfessionalApi } from '@/lib/platform/client';
import { localeNames } from '@/lib/platform/content';
import type { VersionDTO } from '@/lib/platform/types';

/** Existing activity lists used version IDs; there is no complete version-list API. */
export default function PublishedVersionPicker({ api, organizationId, knownVersions = [], value, onChange, onError, disabled, active = true }: {
  api: ProfessionalApi; organizationId: string; knownVersions?: VersionDTO[]; value: string;
  onChange: (id: string) => void; onError: (error: unknown) => void; disabled: boolean; active?: boolean;
}) {
  const [usedIds, setUsedIds] = useState<string[]>([]), [loaded, setLoaded] = useState<VersionDTO[]>([]), [count, setCount] = useState(0);
  const [loading, setLoading] = useState(false), [notice, setNotice] = useState(''), [manual, setManual] = useState(false);
  const alive = useRef(true), started = useRef(false);
  useEffect(() => { alive.current = true; return () => { alive.current = false; }; }, [api, organizationId]);
  const loadBatch = async (ids: string[]) => {
    const snapshots = await Promise.all(ids.map(async id => {
      try {
        const snapshot = await api.request<VersionDTO>(`/api/v1/professional/questionnaire-versions/${encodeURIComponent(id)}`);
        return snapshot.id === id && snapshot.organization_id === organizationId && snapshot.content?.locales?.length ? snapshot : null;
      } catch (error) {
        if (alive.current && error instanceof PlatformClientError && [401, 403].includes(error.status)) onError(error);
        return null;
      }
    }));
    if (!alive.current) return;
    setLoaded(old => [...old, ...snapshots.filter((snapshot): snapshot is VersionDTO => snapshot !== null).filter(snapshot => !old.some(existing => existing.id === snapshot.id))]);
    if (snapshots.some(snapshot => !snapshot)) setNotice('Some version details are unavailable. You can still enter a published version ID supplied by your practice.');
  };
  useEffect(() => {
    if (!active || started.current) return;
    started.current = true; setLoading(true);
    void (async () => {
      try {
        const data = await api.request<{ series: Array<{ questionnaire_version_id: string }> }>(`/api/v1/professional/analytics?organization_id=${encodeURIComponent(organizationId)}`);
        if (!alive.current) return;
        const ids = Array.from(new Set((data.series ?? []).map(item => item.questionnaire_version_id)));
        setUsedIds(ids); await loadBatch(ids.slice(0, 10)); if (alive.current) setCount(Math.min(10, ids.length));
      } catch (error) {
        if (alive.current) { setNotice('Used versions could not be loaded. Recently viewed versions remain available, or enter a published version ID.'); if (error instanceof PlatformClientError && [401, 403].includes(error.status)) onError(error); }
      } finally { if (alive.current) setLoading(false); }
    })();
  }, [active, api, organizationId]);
  const choices = [...knownVersions, ...loaded].filter((snapshot, index, all) => snapshot.organization_id === organizationId && all.findIndex(other => other.id === snapshot.id) === index);
  const chosen = choices.find(snapshot => snapshot.id === value), useId = manual || (!!value && !chosen);
  return <div className="care-version-picker">
    <label className="professional-label">Published questionnaire<select className="neo-input" aria-label="Published questionnaire" aria-describedby="published-version-guidance" value={useId ? '__manual__' : chosen?.id ?? ''} disabled={disabled} onChange={event => {
      const selected = event.target.value;
      if (selected === '__manual__') { setManual(true); if (chosen) onChange(''); }
      else { setManual(false); onChange(selected); }
    }}><option value="">Choose a known published version</option>{choices.map(snapshot => <option value={snapshot.id} key={snapshot.id}>{snapshot.content.title[snapshot.content.locales[0]]} - Revision {snapshot.source_revision} - {snapshot.content.locales.map(locale => localeNames[locale]).join(', ')}</option>)}<option value="__manual__">Enter another published version ID</option></select></label>
    <p id="published-version-guidance" className="professional-muted">Choose a version used by this practice or published/viewed in this session. The current API does not list every previously published version. Each selected patient receives an independent assignment.</p>
    {loading && <p role="status">Loading authorized published versions...</p>}{notice && <p role="status">{notice}</p>}
    {!loading && !choices.length && <p>No known published versions are available yet. Open a saved published revision from Questionnaires, or choose the ID entry option.</p>}
    {useId && <NeoInput label="Published questionnaire version ID" aria-label="Published questionnaire version ID" value={value} disabled={disabled} onChange={event => onChange(event.target.value.trim())} />}
    {chosen && !useId && <details><summary>Selected version details</summary><p>{chosen.content.locales.map(locale => localeNames[locale]).join(', ')}; published revision {chosen.source_revision}</p><p>Version ID: <code>{chosen.id}</code></p></details>}
    {count < usedIds.length && <NeoButton variant="ghost" disabled={disabled || loading} onClick={() => {
      setLoading(true); void loadBatch(usedIds.slice(count, count + 10)).finally(() => { if (alive.current) { setCount(old => Math.min(old + 10, usedIds.length)); setLoading(false); } });
    }}>Load more used versions</NeoButton>}
  </div>;
}
