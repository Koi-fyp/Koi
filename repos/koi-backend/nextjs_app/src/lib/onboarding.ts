import { auth } from './firebase';
import { notifyAvatarPreferenceChanged } from '@/lib/avatar/avatarPreference';

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
  } catch {
    throw new Error('Your choice is saved on this device, but could not sync to your account. Check your connection and retry.');
  }

  if (auth?.currentUser?.uid !== uid) throw new Error('Your account changed. Review your companion selection for the current account.');
  localStorage.setItem('koi_onboarding_complete', 'true');
}

export function isOnboardingComplete(): boolean {
  const win = globalThis.window;
  if (!win) return false;
  return win.localStorage.getItem('koi_onboarding_complete') === 'true';
}
