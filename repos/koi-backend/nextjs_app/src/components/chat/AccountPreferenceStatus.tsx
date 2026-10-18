'use client';
import { useCallback, useSyncExternalStore } from 'react';
import { ACCOUNT_SYNC_CHANGED, accountSyncStatus, syncAccountPreferences } from '@/lib/preferences/preferenceSync';

export default function AccountPreferenceStatus({ uid }: { uid?: string }) {
  const subscribe = useCallback((changed: () => void) => {
    const listener = (event: Event) => { if ((event as CustomEvent).detail?.uid === uid) changed(); };
    window.addEventListener(ACCOUNT_SYNC_CHANGED, listener);
    return () => window.removeEventListener(ACCOUNT_SYNC_CHANGED, listener);
  }, [uid]);
  const status = useSyncExternalStore(subscribe, () => uid ? accountSyncStatus(uid) : undefined, () => undefined);
  if (!uid) return null;
  if (!status) return null;
  const message = status === 'synced' ? 'Account preference check completed.' : status === 'checking' ? 'Checking account preferences; local choices remain available.' : status === 'permission-denied' ? 'Account sync was denied. Your saved local choices remain available.' : status === 'offline' ? 'Offline. Your saved local choices will sync when connected.' : 'Account sync is unavailable. Your saved local choices remain available.';
  return <div role="status" style={{ fontSize: 13 }}><p>{message}</p>{status !== 'synced' && status !== 'checking' && <button type="button" onClick={() => { void syncAccountPreferences(uid); }}>Retry account sync</button>}</div>;
}
