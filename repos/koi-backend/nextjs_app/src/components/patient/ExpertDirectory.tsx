'use client';
import { useEffect, useRef, useState } from 'react';
import NeoButton from '@/components/ui/NeoButton';
import NeoCard from '@/components/ui/NeoCard';
import NeoInput from '@/components/ui/NeoInput';
import type { ProfessionalApi } from '@/lib/platform/client';
import type { Page } from '@/lib/platform/patient-types';
interface Expert { id: string; display_name: string; bio: string; accepting_new_patients: boolean }
export default function ExpertDirectory({ api, onChoose, onError }: { api: ProfessionalApi; onChoose: (uid: string) => void; onError: (e: unknown) => void }) {
  const [items, setItems] = useState<Expert[]>([]), [cursor, setCursor] = useState<string | null>(null), [search, setSearch] = useState(''), [busy, setBusy] = useState(false), [error, setError] = useState('');
  const alive = useRef(true);
  const load = async (next?: string) => { setBusy(true); setError(''); try { const page = await api.request<Page<Expert>>(`/api/v1/experts${next ? `?cursor=${encodeURIComponent(next)}` : ''}`); if (alive.current) { setItems(old => next ? [...old, ...page.items] : page.items); setCursor(page.next_cursor); } } catch (e) { if (alive.current) { setError('Directory unavailable.'); onError(e); } } finally { if (alive.current) setBusy(false); } };
  useEffect(() => { alive.current = true; void load(); return () => { alive.current = false; }; }, [api]);
  const filtered = items.filter(p => `${p.display_name} ${p.bio}`.toLocaleLowerCase().includes(search.toLocaleLowerCase()));
  return <NeoCard className="professional-card"><h2>Find an expert</h2><NeoInput aria-label="Search loaded expert profiles" label="Search loaded profiles" value={search} onChange={e => setSearch(e.target.value)} />{busy && <p role="status"><span className="neo-spinner" aria-hidden="true" />Loading…</p>}{error && <p role="alert">{error}</p>}{!busy && !filtered.length && <p>No matching profiles in this page. Load more profiles or change your search.</p>}{filtered.map(p => <article className="professional-question" key={p.id}><h3>{p.display_name}</h3><p style={{ whiteSpace: 'pre-wrap' }}>{p.bio}</p><p>{p.accepting_new_patients ? 'Accepting new patients' : 'Not accepting new patients'}</p><NeoButton disabled={!p.accepting_new_patients} onClick={() => onChoose(p.id)}>Choose for application</NeoButton></article>)}{cursor && <NeoButton disabled={busy} onClick={() => void load(cursor)}>Load more profiles</NeoButton>}<NeoButton variant="ghost" disabled={busy} onClick={() => void load()}>Refresh directory</NeoButton></NeoCard>;
}
