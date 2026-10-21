'use client';
import { useEffect, useRef, useState } from 'react';
import NeoButton from '@/components/ui/NeoButton';
import NeoCard from '@/components/ui/NeoCard';
import { useSnackbar } from '@/components/ui/feedback';
import { useUnreadState } from '@/components/messaging/useUnreadMessages';
import { PlatformClientError, type ProfessionalApi } from '@/lib/platform/client';
import type { CareNotification } from '@/lib/platform/community-types';
import type { Page } from '@/lib/platform/patient-types';
import { unreadStore } from '@/lib/platform/messaging/unread-store';

export type NotificationWorkspace = 'patient' | 'professional';
// Generic labels only: a notification never shows message, answer or appointment text.
const notificationLabels: Record<CareNotification['kind'], string> = { new_message: 'New care message', appointment_change: 'Appointment update', assignment: 'Questionnaire assigned', application_state: 'Application update' };
const destinations: Record<NotificationWorkspace, Record<CareNotification['kind'], { href: string; label: string }>> = {
  patient: {
    new_message: { href: '/patient?view=messages#messages', label: 'Open messages' },
    appointment_change: { href: '/patient?view=appointments', label: 'Open appointments' },
    assignment: { href: '/patient?view=questionnaires#questionnaires', label: 'Open questionnaires' },
    application_state: { href: '/patient?view=applications#applications', label: 'View current applications' },
  },
  professional: {
    new_message: { href: '/professional?view=messages#messages', label: 'Open messages' },
    appointment_change: { href: '/professional?view=appointments', label: 'Open appointments' },
    assignment: { href: '/professional?view=analytics#practice-analytics', label: 'Open assignments' },
    application_state: { href: '/professional?view=patients#patients', label: 'Open applications' },
  },
};
export const notificationDestination = (n: CareNotification, workspace: NotificationWorkspace) => destinations[workspace][n.kind];
export const notificationLabel = (n: CareNotification) => notificationLabels[n.kind];
/** Newest first; ties keep a stable id order. */
export const sortNotifications = (items: CareNotification[]) => [...items].sort((a, b) => b.created_at.localeCompare(a.created_at) || b.id.localeCompare(a.id));
export const MAX_MARK_ALL = 50;
const fatal = (e: unknown) => e instanceof PlatformClientError ? [401, 403].includes(e.status) : [401, 403].includes((e as { status?: number } | null)?.status ?? 0);

export default function CareNotifications({ api, onError, workspace = 'patient' }: { api: ProfessionalApi; onError: (e: unknown) => void; workspace?: NotificationWorkspace }) {
  const [items, setItems] = useState<CareNotification[]>([]), [cursor, setCursor] = useState<string | null>(null), [busy, setBusy] = useState(false), [loaded, setLoaded] = useState(false), [error, setError] = useState('');
  const alive = useRef(true), snackbar = useSnackbar(), polled = useUnreadState();
  const load = async (next?: string) => { setBusy(true); setError(''); try { const p = await api.request<Page<CareNotification>>(`/api/v1/notifications${next ? `?cursor=${encodeURIComponent(next)}` : ''}`); if (alive.current) { setItems(old => next ? [...old, ...p.items.filter(n => !old.some(o => o.id === n.id))] : p.items); setCursor(p.next_cursor); setLoaded(true); } } catch (e) { if (alive.current) { setError('Notifications unavailable.'); onError(e); } } finally { if (alive.current) setBusy(false); } };
  useEffect(() => { alive.current = true; void load(); return () => { alive.current = false; }; }, [api]);
  // Reuse the single nav poller: merge what it found instead of polling again here.
  useEffect(() => {
    if (!polled.loaded || !polled.notices.length) return;
    setItems(old => { const byId = new Map(old.map(n => [n.id, n])); for (const n of polled.notices) byId.set(n.id, n.read_at || !byId.get(n.id)?.read_at ? n : byId.get(n.id)!); return [...byId.values()]; });
  }, [polled]);
  const markOne = async (id: string) => {
    const n = await api.request<CareNotification>(`/api/v1/notifications/${encodeURIComponent(id)}/read`, 'POST', {});
    if (!alive.current) return;
    setItems(old => old.map(item => item.id === id ? n : item));
    if (unreadStore.get().notices.some(item => item.id === id)) unreadStore.patch(id, n);
  };
  const read = async (id: string) => { setBusy(true); try { await markOne(id); } catch (e) { if (alive.current) { setError('Unable to mark notification read.'); onError(e); } } finally { if (alive.current) setBusy(false); } };
  const readAll = async () => {
    setBusy(true); setError('');
    try {
      // Sequential and capped; an already-read or vanished notice is skipped.
      for (const n of sortNotifications(items).filter(item => !item.read_at).slice(0, MAX_MARK_ALL)) {
        try { await markOne(n.id); } catch (e) { if (fatal(e)) throw e; }
        if (!alive.current) return;
      }
      snackbar.success('Notifications marked as read');
    } catch (e) { if (alive.current) { setError('Unable to mark notifications read.'); onError(e); } }
    finally { if (alive.current) setBusy(false); }
  };
  const sorted = sortNotifications(items), unread = sorted.filter(n => !n.read_at).length;
  return <NeoCard className="professional-card"><div className="professional-row professional-between"><h3>Notifications</h3>{unread > 0 && <NeoButton variant="secondary" disabled={busy} onClick={() => void readAll()}>Mark all as read</NeoButton>}</div>
    <p>{unread} unread in loaded notifications</p>{busy && <p role="status"><span className="neo-spinner" aria-hidden="true" />Loading…</p>}{error && <p role="alert">{error}</p>}
    {loaded && !busy && !items.length && <p>No notifications yet. Updates about your care appear here.</p>}
    <ul className="care-notification-list">{sorted.map(n => { const destination = notificationDestination(n, workspace); return <li key={n.id} className="care-notification" data-unread={!n.read_at || undefined}>
      {!n.read_at && <span className="care-new-badge">New</span>}
      <p><strong>{notificationLabel(n)}</strong> · <time dateTime={n.created_at}>{new Date(n.created_at).toLocaleString()}</time></p>
      <div className="professional-row"><a className="neo-btn-ghost" href={destination.href} onClick={() => { if (!n.read_at) void markOne(n.id).catch(() => undefined); }}>{destination.label}</a>{!n.read_at && <NeoButton variant="ghost" disabled={busy} onClick={() => void read(n.id)}>Mark as read</NeoButton>}</div>
      <details><summary>Notification details</summary><code>{n.kind}</code></details>
    </li>; })}</ul>
    {cursor && <NeoButton disabled={busy} onClick={() => void load(cursor)}>More notifications</NeoButton>}<NeoButton variant="ghost" disabled={busy} onClick={() => void load()}>Refresh notifications</NeoButton></NeoCard>;
}
