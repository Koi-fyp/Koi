'use client';
import { useCallback, useEffect, useState } from 'react';
import { loadUserPreferences, PREFERENCES_CHANGED, type UserPreferences } from '@/lib/preferences/userPreferences';
type State = { status: 'loading' } | { status: 'ready'; uid: string | null; profile: UserPreferences | null } | { status: 'error'; uid: string };
export function useUserPreferences(uid: string | undefined, authLoading = false) {
  const [state, setState] = useState<State>({ status: 'loading' });
  const [revision, setRevision] = useState(0);
  const retry = useCallback(() => setRevision(value => value + 1), []);
  useEffect(() => {
    if (authLoading) return;
    if (!uid) { setState({ status: 'ready', uid: null, profile: null }); return; }
    let active = true;
    setState(previous => previous.status === 'ready' && previous.uid === uid ? previous : { status: 'loading' });
    void loadUserPreferences(uid).then(profile => { if (active) setState({ status: 'ready', uid, profile }); })
      .catch(() => { if (active) setState({ status: 'error', uid }); });
    return () => { active = false; };
  }, [uid, authLoading, revision]);
  useEffect(() => {
    const changed = (event: Event) => { if (!(event as CustomEvent).detail?.uid || (event as CustomEvent).detail.uid === uid) retry(); };
    window.addEventListener(PREFERENCES_CHANGED, changed);
    window.addEventListener('focus', retry); // Refresh after another tab's preference write.
    return () => { window.removeEventListener(PREFERENCES_CHANGED, changed); window.removeEventListener('focus', retry); };
  }, [uid, retry]);
  const current: State = authLoading || (state.status !== 'loading' && state.uid !== (uid ?? null)) ? { status: 'loading' } : state;
  return { state: current, retry };
}
