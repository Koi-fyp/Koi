import { db, type UserRecord } from '@/lib/db';

/** Additive local field, no table/schema migration and no automatic cloud write. */
export type UserPreferences = UserRecord & { displayName?: string };
export type PreferenceChanges = Pick<UserPreferences, 'avatar' | 'companion' | 'language' | 'notificationsEnabled' | 'notificationTime' | 'displayName'>;
export const PREFERENCES_CHANGED = 'koi-avatar-preference-changed';
export const validTime = (value: unknown): value is string => typeof value === 'string' && /^([01]\d|2[0-3]):[0-5]\d$/.test(value);
export function notifyPreferencesChanged(uid: string) {
  if (typeof window !== 'undefined') window.dispatchEvent(new CustomEvent(PREFERENCES_CHANGED, { detail: { uid } }));
}
export async function loadUserPreferences(uid: string): Promise<UserPreferences | null> {
  if (!uid.trim()) throw new Error('A preference owner is required.');
  const row = await db.users.where('uid').equals(uid).first() as UserPreferences | undefined;
  return row ?? null;
}
export async function saveUserPreferences(uid: string, changes: PreferenceChanges): Promise<void> {
  if (!uid.trim()) throw new Error('A preference owner is required.');
  const fields: PreferenceChanges = {};
  for (const key of Object.keys(changes)) {
    if (!['avatar', 'companion', 'language', 'notificationsEnabled', 'notificationTime', 'displayName'].includes(key)) throw new Error('Unsupported preference.');
  }
  if (changes.language !== undefined) {
    if (!['en', 'ur'].includes(changes.language)) throw new Error('Choose a supported language.');
    fields.language = changes.language;
  }
  if (changes.notificationTime !== undefined) {
    if (!validTime(changes.notificationTime)) throw new Error('Choose a valid time.');
    fields.notificationTime = changes.notificationTime;
  }
  if (changes.notificationsEnabled !== undefined) {
    if (typeof changes.notificationsEnabled !== 'boolean') throw new Error('Choose a valid reminder preference.');
    fields.notificationsEnabled = changes.notificationsEnabled;
  }
  if (changes.displayName !== undefined) {
    if (typeof changes.displayName !== 'string' || [...changes.displayName.trim()].length > 64 || /[\u0000-\u001f\u007f]/.test(changes.displayName)) throw new Error('Use a nickname of up to 64 characters.');
    fields.displayName = changes.displayName.trim();
  }
  if (changes.companion !== undefined || changes.avatar !== undefined) {
    const pairs = { aisha: 'female_human', raza: 'male_human', koi: 'fox' } as const;
    if (!changes.companion || !Object.hasOwn(pairs, changes.companion) || pairs[changes.companion] !== changes.avatar) throw new Error('Choose a matching companion and avatar.');
    fields.companion = changes.companion; fields.avatar = changes.avatar;
  }
  await db.transaction('rw', db.users, async () => {
    const existing = await db.users.where('uid').equals(uid).first();
    if (existing?.id != null) await db.users.update(existing.id, fields);
    else await db.users.add({ uid, ...fields });
  });
  notifyPreferencesChanged(uid);
}

/** A local clock comparison only. No delivery, completion or scheduler is implied. */
export function reminderStatus(profile: UserPreferences | null, now: Date): string {
  if (!Number.isFinite(now.getTime())) return 'Device time unavailable; no message is scheduled.';
  if (profile?.notificationsEnabled !== true) return profile?.notificationsEnabled === false ? 'Preference off; no notifications scheduled.' : 'No check-in preference saved.';
  if (!validTime(profile.notificationTime)) return 'Choose a preferred time. Message delivery is unavailable.';
  const clock = `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;
  return `${clock >= profile.notificationTime ? 'Preferred time reached' : 'Preferred time later today'} (${profile.notificationTime}, device time). No message is scheduled.`;
}
