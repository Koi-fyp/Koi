'use client';
import { useEffect, useRef, useState } from 'react';
import { useProfessionalAuth } from '@/lib/platform/professional-auth';
import { professionalApi } from '@/lib/platform/client';
import { platformLinks } from '@/lib/platform/navigation';
import { navPollMs } from '@/lib/platform/poll-config';
import type { CapabilitiesDTO } from '@/lib/platform/types';

export default function PlatformNavigation({ expanded = false, compact = false }: { expanded?: boolean; compact?: boolean }) {
  const auth = useProfessionalAuth(), current = useRef(auth.currentUser); current.current = auth.currentUser;
  const [state, setState] = useState<{ uid: string; caps: CapabilitiesDTO } | null>(null), [error, setError] = useState(false);
  const uid = auth.user?.uid;
  useEffect(() => {
    setState(null); setError(false); if (!uid) return;
    let alive = true, loading = false;
    const api = professionalApi(uid, () => current.current());
    const refresh = async () => {
      if (document.hidden) { if (alive) setState(null); return; } if (loading) return; loading = true;
      try { const caps = await api.request<CapabilitiesDTO>('/api/v1/me/capabilities'); if (alive && current.current()?.uid === uid && !document.hidden && caps.uid === uid) { setState({ uid, caps }); setError(false); } }
      catch { if (alive) { setState(null); setError(true); } } finally { loading = false; }
    };
    void refresh(); const timer = setInterval(refresh, navPollMs());
    const lock = () => { setState(null); }; window.addEventListener('offline', lock); document.addEventListener('visibilitychange', refresh); window.addEventListener('focus', refresh);
    return () => { alive = false; api.dispose(); clearInterval(timer); window.removeEventListener('offline', lock); document.removeEventListener('visibilitychange', refresh); window.removeEventListener('focus', refresh); };
  }, [uid]);
  useEffect(() => {
    const id = window.location.hash.slice(1); if (!id || id.includes('=')) return;
    const reveal = () => { const target = document.getElementById(id); if (!target) return false; target.scrollIntoView({ behavior: 'auto', block: 'start' }); return true; };
    if (reveal()) return;
    const observer = new MutationObserver(() => { if (reveal()) observer.disconnect(); }); observer.observe(document.body, { childList: true, subtree: true });
    const stop = setTimeout(() => observer.disconnect(), 30000); return () => { observer.disconnect(); clearTimeout(stop); };
  }, []);
  const caps = uid && state?.uid === uid ? state.caps : null;
  const links = <div role={expanded ? 'navigation' : 'group'} aria-label="KOI account navigation" className="flex flex-col gap-2">{platformLinks(caps).map(link => <a key={link.href} href={link.href} className="neo-btn-ghost motion-reduce:!transform-none" style={{ textAlign: 'left', fontSize: '.875rem' }}>{link.label}</a>)}{auth.loading || uid && !caps && !error ? <span role="status"><span className="neo-spinner" aria-hidden="true" /> Checking access…</span> : null}{error && <p role="status">Account access unavailable. Clinical links are locked.</p>}</div>;
  if (expanded) return links;
  return <details className="relative"><summary aria-label="KOI menu" className="neo-btn-ghost motion-reduce:!transform-none" style={{ cursor: 'pointer', fontSize: '.875rem', ...(compact ? { padding: '.25rem .5rem', minHeight: 44 } : {}) }}>{compact ? <><span className="sm:hidden">Menu</span><span className="hidden sm:inline">KOI menu</span></> : 'KOI menu'}</summary><div className="absolute right-0 z-[60] bg-white border-[3px] border-black rounded-2xl shadow-[4px_4px_0_#000] p-3" style={{ width: 'min(290px, calc(100vw - 2rem))', maxHeight: '70vh', overflowY: 'auto' }}>{links}</div></details>;
}
