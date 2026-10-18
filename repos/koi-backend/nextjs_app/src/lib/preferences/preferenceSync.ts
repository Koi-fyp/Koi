import { auth } from '@/lib/firebase';
import { db } from '@/lib/db';
import { loadUserPreferences, notifyPreferencesChanged, type UserPreferences } from './userPreferences';
import { readOwnedAccountPreferences, writeOwnedAccountPreferences, type AccountPreferenceFields } from './accountPreferenceSync.proposed';

export const ACCOUNT_SYNC_CHANGED = 'koi-account-preference-sync';
type Status = 'checking' | 'synced' | 'offline' | 'permission-denied' | 'unavailable';
const statuses = new Map<string, Status>();
const running = new Map<string, Promise<void>>();
export const accountSyncStatus = (uid: string) => statuses.get(uid);
function publish(uid: string, status: Status) {
  if (auth?.currentUser?.uid !== uid) return;
  statuses.set(uid, status);
  if (typeof window !== 'undefined') window.dispatchEvent(new CustomEvent(ACCOUNT_SYNC_CHANGED, { detail: { uid } }));
}
const owned = (uid: string) => auth?.currentUser?.uid === uid;

/** Single-flight, local-first. Only acknowledged revisions are cleared; no keys or message records accessed. */
export function syncAccountPreferences(uid: string): Promise<void> {
  if (!owned(uid)) return Promise.resolve();
  if (running.has(uid)) return running.get(uid)!;
  const task = synchronize(uid).finally(() => { running.delete(uid); });
  running.set(uid, task);
  return task;
}
async function synchronize(uid: string) {
  if (typeof navigator !== 'undefined' && navigator.onLine === false) { publish(uid, 'offline'); return; }
  publish(uid, 'checking');
  try {
    const signal = new AbortController().signal;
    const beforeRead = await loadUserPreferences(uid);
    const localVersion = JSON.stringify(beforeRead?.accountSync ?? null);
    const remote = await readOwnedAccountPreferences(uid, signal);
    if (!owned(uid)) return;
    await db.transaction('rw', db.users, async () => {
      const local = await loadUserPreferences(uid);
      if (!owned(uid)) return;
      const legacy = local && !local.accountSync?.initialized ? Object.fromEntries(['avatar', 'companion', 'language'].filter(key => local[key as keyof UserPreferences] !== undefined).map(key => [key, local[key as keyof UserPreferences]])) : {};
      // Preserve pre-integration local selections, including legacy fox, by synchronizing them once.
      if (legacy.avatar && !legacy.companion) legacy.companion = legacy.avatar === 'fox' ? 'koi' : legacy.avatar === 'female_human' ? 'aisha' : 'raza';
      if (legacy.companion && !legacy.avatar) legacy.avatar = legacy.companion === 'koi' ? 'fox' : legacy.companion === 'aisha' ? 'female_human' : 'male_human';
      const pending = { ...legacy, ...local?.accountSync?.pending };
      // Another tab may have acknowledged a newer edit while this read was in flight.
      const unchanged = localVersion === JSON.stringify(local?.accountSync ?? null);
      const fields = remote.status === 'server-read' && unchanged ? { ...remote.preferences } : {};
      if (fields.avatar && !fields.companion) fields.companion = fields.avatar === 'fox' ? 'koi' : fields.avatar === 'female_human' ? 'aisha' : 'raza';
      if (fields.companion && !fields.avatar) fields.avatar = fields.companion === 'koi' ? 'fox' : fields.companion === 'aisha' ? 'female_human' : 'male_human';
      // Never overwrite a pending local edit with an older account value.
      const initialized = local?.accountSync?.initialized === true;
      const safeFields = Object.fromEntries(Object.entries(fields).filter(([key]) => !(key in pending) && (initialized || local?.[key as keyof UserPreferences] === undefined)));
      const update = { ...safeFields, accountSync: { pending: pending as AccountPreferenceFields, revision: local?.accountSync?.revision ?? 0, initialized: true } };
      if (local?.id != null) await db.users.update(local.id, update);
      else await db.users.add({ uid, ...update });
    });
    notifyPreferencesChanged(uid);
    while (owned(uid)) {
      const local = await loadUserPreferences(uid);
      const pending = local?.accountSync?.pending ?? {};
      if (!Object.keys(pending).length) { publish(uid, 'synced'); return; }
      const revision = local!.accountSync!.revision;
      await writeOwnedAccountPreferences(uid, pending as AccountPreferenceFields, signal);
      if (!owned(uid)) return;
      await db.transaction('rw', db.users, async () => {
        const current = await loadUserPreferences(uid);
        if (!owned(uid) || current?.id == null || current.accountSync?.revision !== revision) return;
        await db.users.update(current.id, { accountSync: { pending: {}, revision, initialized: true } } as Partial<UserPreferences>);
      });
      notifyPreferencesChanged(uid);
    }
  } catch (error) {
    publish(uid, error && typeof error === 'object' && 'reason' in error && error.reason === 'permission-denied' ? 'permission-denied' : 'unavailable');
  }
}
