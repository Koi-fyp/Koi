'use client';
import { useEffect, useState, type ReactNode } from 'react';
import { useCareReveal } from './care-focus';
import { revealCareElement } from './care-focus';
import ScrollButtons from '@/components/ui/ScrollButtons';
import { useUnreadState } from '@/components/messaging/useUnreadMessages';
import { badgeText, unreadMessageNotices, unreadOtherNotices } from '@/lib/platform/messaging/model';

export interface WorkspaceView { id: string; label: string; description: string; anchor?: string }
export const professionalViews: WorkspaceView[] = [
  { id: 'dashboard', label: 'Practice overview', description: 'Your practice activity, profile and shortcuts to care workflows.', anchor: 'practice-dashboard' },
  { id: 'questionnaires', label: 'Questionnaires', description: 'Create, review and publish custom questionnaires.', anchor: 'professional-questionnaires' },
  { id: 'patients', label: 'Patients & assignments', description: 'Manage applications, relationships and questionnaire assignments.', anchor: 'patients' },
  { id: 'submissions', label: 'Submission review', description: 'Review submitted answers and record your professional conclusions.', anchor: 'submissions' },
  { id: 'analytics', label: 'Assignments & Submissions', description: 'Track questionnaire assignments and submitted attempts. These operational counts do not measure clinical improvement.', anchor: 'practice-analytics' },
  { id: 'messages', label: 'Messages', description: 'Your human conversations with patients.', anchor: 'messages' },
  { id: 'appointments', label: 'Appointments', description: 'All appointments across your patients, latest change first. Propose times on requests, or select a patient below.' },
  { id: 'notifications', label: 'Notifications', description: 'Updates about appointments, applications and patient messages.', anchor: 'notifications' },
];
export const generalViews: WorkspaceView[] = [
  { id: 'home', label: 'Care Home', description: 'Find a psychologist, track applications and accept practice invitations.' },
  { id: 'experts', label: 'Find a Psychologist', description: 'Explore professional profiles and apply to a practice.', anchor: 'experts' },
  { id: 'applications', label: 'My Applications', description: 'Track application decisions and the existing demo-payment steps.', anchor: 'applications' },
  { id: 'become-psychologist', label: 'Become a Psychologist', description: 'Professional registration information and access for already verified psychologists.' },
  { id: 'notifications', label: 'Notifications', description: 'Updates about your applications and care.', anchor: 'notifications' },
];
// Keep discovery/application views routable for existing links and additional-practice management.
export const patientViews: WorkspaceView[] = [
  { id: 'home', label: 'My Care / Overview', description: 'Your connected care team, assigned questionnaires and next steps.' },
  ...generalViews.filter(v => ['experts', 'applications', 'become-psychologist'].includes(v.id)),
  { id: 'care', label: 'My Psychologist', description: 'Your active care relationships.', anchor: 'care' },
  { id: 'questionnaires', label: 'Questionnaires', description: 'Complete assigned forms or return to a saved attempt.', anchor: 'questionnaires' },
  { id: 'messages', label: 'Messages', description: 'Your human conversations with your care team.', anchor: 'messages' },
  { id: 'appointments', label: 'Appointments', description: 'All your appointments, latest change first. Request an appointment or respond to a proposed time.' },
  { id: 'notifications', label: 'Notifications', description: 'Updates about your applications and care.', anchor: 'notifications' },
];
export function viewFromLocation(views: WorkspaceView[], fallback: string): string {
  const params = new URLSearchParams(window.location.search);
  if (params.has('version') && views === professionalViews) return 'questionnaires';
  const requested = params.get('view');
  if (views.some(v => v.id === requested)) return requested!;
  // Preserve section-only links, including the original appointments #care link.
  if (!requested) {
    const anchor = window.location.hash.slice(1);
    const match = views.find(v => v.anchor === anchor);
    if (match) return match.id;
  }
  return fallback;
}
export function useWorkspaceView(views: WorkspaceView[], fallback: string) {
  const [view, setView] = useState(fallback);
  useEffect(() => {
    const sync = () => setView(viewFromLocation(views, fallback));
    sync(); window.addEventListener('popstate', sync); window.addEventListener('hashchange', sync);
    return () => { window.removeEventListener('popstate', sync); window.removeEventListener('hashchange', sync); };
  }, [views, fallback]);
  return view;
}
export function useWorkspaceSearchParam(name: string) {
  const [value, setValue] = useState<string | null>(null);
  useEffect(() => {
    const sync = () => setValue(new URLSearchParams(window.location.search).get(name));
    sync(); window.addEventListener('popstate', sync); window.addEventListener('hashchange', sync);
    return () => { window.removeEventListener('popstate', sync); window.removeEventListener('hashchange', sync); };
  }, [name]);
  return value;
}
export function useWorkspaceFragment() {
  const [fragment, setFragment] = useState('');
  useEffect(() => {
    const sync = () => setFragment(window.location.hash.slice(1));
    sync(); window.addEventListener('popstate', sync); window.addEventListener('hashchange', sync);
    return () => { window.removeEventListener('popstate', sync); window.removeEventListener('hashchange', sync); };
  }, []);
  return fragment;
}
export function navigateWorkspace(href: string) {
  const url = new URL(href, window.location.href);
  if (url.origin !== window.location.origin) return;
  if (url.href !== window.location.href) window.history.pushState(null, '', url);
  window.dispatchEvent(new PopStateEvent('popstate'));
}
export function workspaceHref(base: string, view: WorkspaceView, contextParams: Record<string, string> = {}) {
  const params = new URLSearchParams({ ...contextParams, view: view.id });
  return `${base}?${params}${view.anchor ? `#${view.anchor}` : ''}`;
}
/** Role names shown to people; the role itself always comes from server capabilities. */
export type WorkspaceRole = 'General User' | 'Patient' | 'Psychologist';
export default function WorkspaceFrame({ base, views, view, children, secondaryViews = [], workspaceLabel, contextParams = {}, role }: { base: string; views: WorkspaceView[]; view: string; children: ReactNode; secondaryViews?: WorkspaceView[]; workspaceLabel?: string; contextParams?: Record<string, string>; role?: WorkspaceRole }) {
  const selected = [...views, ...secondaryViews].find(v => v.id === view);
  useCareReveal('workspace-heading', view);
  const unread = useUnreadState().notices, counts: Record<string, number> = { messages: unreadMessageNotices(unread).length, notifications: unreadOtherNotices(unread).length };
  const label = (item: WorkspaceView) => <>{item.label}{counts[item.id] > 0 && <> <span aria-hidden="true" className="professional-badge">{badgeText(counts[item.id])}</span><span className="sr-only"> ({counts[item.id]} unread)</span></>}</>;
  return <div className="care-workspace" onClick={event => {
    const link = (event.target as HTMLElement).closest('a');
    if (!link || event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || link.target || link.hasAttribute('download')) return;
    const url = new URL(link.href);
    if (url.origin !== window.location.origin || url.pathname !== base) return;
    Object.entries(contextParams).forEach(([key, value]) => { if (!url.searchParams.has(key)) url.searchParams.set(key, value); });
    event.preventDefault(); navigateWorkspace(url.href);
    if (url.search === window.location.search && link.getAttribute('href')?.startsWith('#')) {
      requestAnimationFrame(() => revealCareElement(document.getElementById(url.hash.slice(1))));
    }
  }}>
    <nav className="care-sidebar" aria-label={base === '/professional' ? 'Practice navigation' : 'Care navigation'}>
      <p className={role ? 'care-role-badge' : 'professional-label'}>{workspaceLabel ?? 'KOI Care'}</p>
      {views.map(item => <a key={item.id} href={workspaceHref(base, item, contextParams)} aria-current={view === item.id ? 'page' : undefined}>{label(item)}</a>)}
      {secondaryViews.length > 0 && <details className="care-disclosure" open={secondaryViews.some(item => item.id === view) || undefined}><summary>Additional care options</summary>{secondaryViews.map(item => <a key={item.id} href={workspaceHref(base, item, contextParams)} aria-current={view === item.id ? 'page' : undefined}>{item.label}</a>)}</details>}
      <a href="/account">{base === '/patient' ? 'Account & Access' : 'Account & access'}</a>
    </nav>
    <div className="care-content"><header className="care-view-heading">{role && <p className="care-role-badge" data-role={role}><span className="sr-only">Your role: </span>{role}</p>}<h1 id="workspace-heading" tabIndex={-1}>{selected?.label ?? 'Care workspace'}</h1><p className="professional-muted">{selected?.description}</p></header>{children}</div>
    <ScrollButtons />
  </div>;
}
