'use client';
import { useEffect, useState } from 'react';
import { liveQuery } from 'dexie';
import { activityLedger } from '@/lib/activities/activityLedger';
import { readCheckIns, type SavedCheckIn } from '@/lib/checkins/checkInService';
export type ActivityData = Awaited<ReturnType<typeof activityLedger.read>>;
type State = { owner: string; status: 'ready'; ledger: ActivityData; entries: SavedCheckIn[]; unreadable: number; locked: boolean } | { owner: string; status: 'loading' | 'error' };
export function useActivityData(uid?: string) {
  const [state, setState] = useState<State>({ owner: '', status: 'loading' });
  useEffect(() => {
    if (!uid) return;
    let active = true;
    const subscription = liveQuery(async () => {
      const ledger = await activityLedger.read(uid);
      try { return { owner: uid, status: 'ready' as const, ledger, ...await readCheckIns(uid), locked: false }; }
      catch { return { owner: uid, status: 'ready' as const, ledger, entries: [], unreadable: 0, locked: true }; }
    }).subscribe({ next: result => { if (active) setState(result); }, error: () => { if (active) setState({ owner: uid, status: 'error' }); } });
    return () => { active = false; subscription.unsubscribe(); };
  }, [uid]);
  return state.owner === uid ? state : { owner: uid ?? '', status: 'loading' as const };
}
