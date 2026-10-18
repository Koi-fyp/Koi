import { auth, firestore } from '../firebase';
import { doc, setDoc, type Firestore } from 'firebase/firestore';
import { isLegacyMessagePath, repathLegacyMessage, reviveMessageData } from './messageSync';

export interface SyncItem {
  collection: string;
  docId: string;
  data: Record<string, unknown>;
  priority: number; // 1=crisis, 2=mood, 3=messages, 4=tasks/user
  timestamp?: number;
}

const QUEUE_KEY = 'koi_sync_queue';

function getReadyFirestore(): Firestore | null {
  return firestore?.app ? firestore : null;
}

function loadQueue(): SyncItem[] {
  try {
    return JSON.parse(localStorage.getItem(QUEUE_KEY) || '[]');
  } catch {
    return [];
  }
}

function saveQueue(items: SyncItem[]): void {
  localStorage.setItem(QUEUE_KEY, JSON.stringify(items));
}

function pushPending(item: SyncItem): void {
  const queue = loadQueue();
  queue.push({ ...item, timestamp: Date.now() });
  saveQueue(queue);
}

const itemKey = (item: SyncItem) => `${item.collection}/${item.docId}@${item.timestamp ?? ''}`;

/** One-time move of the signed-in owner's queued root-path messages to users/{uid}/...; synchronous, so atomic. */
function repathLegacyItems(uid: string | undefined): void {
  if (!uid) return;
  const queue = loadQueue();
  let changed = false;
  const next = queue.map(item => {
    const moved = repathLegacyMessage(item, uid);
    if (moved) changed = true;
    return moved ?? item;
  });
  if (changed) saveQueue(next);
}

let flushing: Promise<void> | null = null;
async function flushOnce(): Promise<void> {
  const activeFirestore = getReadyFirestore();
  repathLegacyItems(auth?.currentUser?.uid);
  if (!activeFirestore) return;
  // Root-path messages can never pass the phase-1 rules; they wait for their owner to sign in and be re-pathed.
  const items = loadQueue().filter(item => !isLegacyMessagePath(item.collection)).sort((a, b) => a.priority - b.priority);
  const sent = new Set<string>();
  for (const item of items) {
    try {
      await setDoc(doc(activeFirestore, item.collection, item.docId), reviveMessageData(item.collection, item.data), { merge: true });
      sent.add(itemKey(item));
    } catch {
      // Kept for the next reconnect, app start or sign-in.
    }
  }
  // Re-read: items enqueued during this flush are kept.
  if (sent.size) saveQueue(loadQueue().filter(item => !sent.has(itemKey(item))));
}
function flushQueue(): Promise<void> {
  if (!flushing) flushing = flushOnce().finally(() => { flushing = null; });
  return flushing;
}

if (typeof window !== 'undefined') {
  window.addEventListener('online', () => void flushQueue());
}

export const syncQueue = {
  enqueue(item: SyncItem): void {
    const activeFirestore = getReadyFirestore();
    if (!activeFirestore) {
      pushPending(item);
      return;
    }

    setDoc(doc(activeFirestore, item.collection, item.docId), item.data, { merge: true }).catch(() => pushPending(item));
  },

  /** Retries pending writes; called on reconnect and on app start / sign-in. */
  flush: flushQueue,

  getPending(): SyncItem[] {
    return loadQueue();
  },

  clearPending(): void {
    saveQueue([]);
  },
};
