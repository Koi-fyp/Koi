import { firestore } from '../firebase';
import { doc, setDoc, type Firestore } from 'firebase/firestore';

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

async function flushQueue(): Promise<void> {
  const activeFirestore = getReadyFirestore();
  if (!activeFirestore) return;
  const items = loadQueue().sort((a, b) => a.priority - b.priority);
  const remaining: SyncItem[] = [];
  for (const item of items) {
    try {
      await setDoc(doc(activeFirestore, item.collection, item.docId), item.data, { merge: true });
    } catch {
      remaining.push(item);
    }
  }
  saveQueue(remaining);
}

if (typeof window !== 'undefined') {
  window.addEventListener('online', () => void flushQueue());
}

export const syncQueue = {
  enqueue(item: SyncItem): void {
    const activeFirestore = getReadyFirestore();
    if (!activeFirestore) {
      const queue = loadQueue();
      queue.push({ ...item, timestamp: Date.now() });
      saveQueue(queue);
      return;
    }

    setDoc(doc(activeFirestore, item.collection, item.docId), item.data, { merge: true }).catch(() => {
      const queue = loadQueue();
      queue.push({ ...item, timestamp: Date.now() });
      saveQueue(queue);
    });
  },

  flush: flushQueue,

  getPending(): SyncItem[] {
    return loadQueue();
  },

  clearPending(): void {
    saveQueue([]);
  },
};
