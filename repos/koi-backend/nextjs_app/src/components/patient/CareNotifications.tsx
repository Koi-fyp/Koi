'use client';
import { useEffect, useRef, useState } from 'react';
import NeoButton from '@/components/ui/NeoButton';
import NeoCard from '@/components/ui/NeoCard';
import type { ProfessionalApi } from '@/lib/platform/client';
import type { CareNotification } from '@/lib/platform/community-types';
import type { Page } from '@/lib/platform/patient-types';
export default function CareNotifications({ api, onError }: { api: ProfessionalApi; onError: (e: unknown) => void }) {
  const [items, setItems] = useState<CareNotification[]>([]), [cursor, setCursor] = useState<string | null>(null), [busy, setBusy] = useState(false), [error, setError] = useState('');
  const alive = useRef(true);
  const load = async (next?: string) => { setBusy(true); setError(''); try { const p = await api.request<Page<CareNotification>>(`/api/v1/notifications${next ? `?cursor=${encodeURIComponent(next)}` : ''}`); if (alive.current) { setItems(old => next ? [...old, ...p.items] : p.items); setCursor(p.next_cursor); } } catch (e) { if (alive.current) { setError('Notifications unavailable.'); onError(e); } } finally { if (alive.current) setBusy(false); } };
  useEffect(() => { alive.current = true; void load(); return () => { alive.current = false; }; }, [api]);
  const read = async (id: string) => { setBusy(true); try { const n = await api.request<CareNotification>(`/api/v1/notifications/${id}/read`, 'POST', {}); if (alive.current) setItems(old => old.map(item => item.id === id ? n : item)); } catch (e) { if (alive.current) { setError('Unable to mark notification read.'); onError(e); } } finally { if (alive.current) setBusy(false); } };
  return <NeoCard className="professional-card"><h3>Notifications</h3><p>{items.filter(n => !n.read_at).length} unread in loaded notifications</p>{busy && <p role="status"><span className="neo-spinner" aria-hidden="true" />Loading…</p>}{error && <p role="alert">{error}</p>}{!busy && !items.length && <p>No notifications.</p>}{items.map(n => <div className="professional-row" key={n.id}><span>{n.kind.replaceAll('_', ' ')} · {new Date(n.created_at).toLocaleString()}</span>{!n.read_at && <NeoButton disabled={busy} onClick={() => void read(n.id)}>Mark read</NeoButton>}</div>)}{cursor && <NeoButton disabled={busy} onClick={() => void load(cursor)}>More notifications</NeoButton>}<NeoButton variant="ghost" disabled={busy} onClick={() => void load()}>Refresh notifications</NeoButton></NeoCard>;
}
