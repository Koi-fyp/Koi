import { auth } from './firebase';
import { notifyAvatarPreferenceChanged } from '@/lib/avatar/avatarPreference';
import { preferenceSyncFailure } from '@/lib/preferences/syncFailure';

export interface OnboardingData {
  avatar: 'female_human' | 'male_human' | 'fox';
  companion: 'aisha' | 'raza' | 'koi';
  language: 'en' | 'ur';
  notificationTime: string;
  notificationsEnabled: boolean;
}

export async function completeOnboarding(data: OnboardingData, onLocalSaved?: () => void): Promise<void> {
  const uid = auth?.currentUser?.uid;
  if (!uid) throw new Error('Sign in before saving your companion selection.');

  // The local profile is the shared source used by chat and the 3D companion.
  try {
    const { db } = await import('./db');
    const existing = await db.users.where('uid').equals(uid).first();
    if (existing?.id == null) {
      await db.users.add({ uid, ...data, onboardingComplete: true, createdAt: new Date().toISOString() });
    } else {
      await db.users.update(existing.id, {
        avatar: data.avatar, companion: data.companion, language: data.language,
        notificationTime: data.notificationTime, notificationsEnabled: data.notificationsEnabled, onboardingComplete: true,
      });
    }
  } catch {
    throw new Error('Your companion choice could not be saved on this device. Please retry before continuing.');
  }

  // The local save is the completion receipt: a later cloud failure must not loop this UID back to setup.
  if (auth?.currentUser?.uid === uid) markOnboardingComplete(uid);
  notifyAvatarPreferenceChanged(uid);
  onLocalSaved?.();

  // Preserve the existing user document shape and merge behavior; never claim success if cloud persistence fails.
  try {
    const { doc, setDoc } = await import('firebase/firestore');
    const { firestore } = await import('./firebase');
    if (!firestore) throw new Error('Firestore is unavailable.');
    await setDoc(doc(firestore, 'users', uid), {
      profile: { avatar: data.avatar, companion: data.companion, language: data.language, notificationTime: data.notificationTime },
      onboarding_complete: true,
    }, { merge: true });
  } catch (reason) {
    throw new Error(`Your choice is saved on this device, but could not sync to your account. ${preferenceSyncFailure(reason)}`);
  }

  if (auth?.currentUser?.uid !== uid) throw new Error('Your account changed. Review your companion selection for the current account.');
}

/** Pre-UID global flag. Read only to migrate the same signed-in user whose local row is already complete. */
const LEGACY_ONBOARDING_KEY = 'koi_onboarding_complete';
export const onboardingStorageKey = (uid: string) => `koi_onboarding_complete_${uid}`;
function storage(): Storage | null {
  try { return globalThis.window?.localStorage ?? null; } catch { return null; }
}
function markOnboardingComplete(uid: string) {
  try { storage()?.setItem(onboardingStorageKey(uid), 'true'); } catch { /* Storage blocked: the user row remains the record. */ }
}

/** Synchronous per-UID check; never consults another identity's flag. */
export function isOnboardingComplete(uid: string | null | undefined): boolean {
  if (!uid) return false;
  try { return storage()?.getItem(onboardingStorageKey(uid)) === 'true'; } catch { return false; }
}

/** Per-UID flag, or a one-time migration of the legacy global flag for the same signed-in owner. */
export async function resolveOnboardingComplete(uid: string): Promise<boolean> {
  if (isOnboardingComplete(uid)) return true;
  let legacy = false;
  try { legacy = storage()?.getItem(LEGACY_ONBOARDING_KEY) === 'true'; } catch { legacy = false; }
  if (!legacy || auth?.currentUser?.uid !== uid) return false;
  try {
    const { db } = await import('./db');
    const row = await db.users.where('uid').equals(uid).first();
    if (!row?.onboardingComplete || auth?.currentUser?.uid !== uid) return false;
  } catch { return false; }
  markOnboardingComplete(uid);
  return true;
}
