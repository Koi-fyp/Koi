'use client';
import { useCallback, useEffect, useState } from 'react';
import { liveQuery } from 'dexie';
import { readProgress, type ProgressSummary } from '@/lib/progress/progressReadModel';

type ProgressState =
  | { status: 'loading'; uid: string }
  | { status: 'ready'; uid: string; summary: ProgressSummary }
  | { status: 'error'; uid: string };

export function useProgress(uid: string | undefined) {
  const [state, setState] = useState<ProgressState | null>(null);
  const [revision, setRevision] = useState(0);
  const retry = useCallback(() => setRevision(value => value + 1), []);
  useEffect(() => {
    if (!uid) return;
    let active = true;
    setState({ status: 'loading', uid });
    const subscription = liveQuery(() => readProgress(uid)).subscribe({
      next: summary => { if (active) setState({ status: 'ready', uid, summary }); },
      error: () => { if (active) setState({ status: 'error', uid }); },
    });
    return () => { active = false; subscription.unsubscribe(); };
  }, [uid, revision]);

  // Hide the previous owner's data in the render that changes UID, before effect cleanup.
  const current = !uid ? { status: 'signed-out' as const }
    : state?.uid === uid ? state : { status: 'loading' as const, uid };
  return { state: current, retry };
}
