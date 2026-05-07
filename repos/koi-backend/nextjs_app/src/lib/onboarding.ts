import { auth } from './firebase';

export interface OnboardingData {
  avatar: 'female_human' | 'male_human' | 'fox';
  companion: 'aisha' | 'raza' | 'koi';
  language: 'en' | 'ur';
  notificationTime: string;
  notificationsEnabled: boolean;
}

export async function completeOnboarding(data: OnboardingData): Promise<void> {
  // Always persist locally first — cloud writes are best-effort
  localStorage.setItem('koi_onboarding_complete', 'true');

  const uid = auth.currentUser?.uid;

  // IndexedDB write
  try {
    const { db } = await import('./db');
    if (uid) {
      const existing = await db.users.where('uid').equals(uid).first();
      if (existing?.id == null) {
        await db.users.add({
          uid,
          ...data,
          onboardingComplete: true,
          createdAt: new Date().toISOString(),
        });
      } else {
        await db.users.update(existing.id, {
          avatar: data.avatar,
          companion: data.companion,
          language: data.language,
          notificationTime: data.notificationTime,
          notificationsEnabled: data.notificationsEnabled,
          onboardingComplete: true,
        });
      }
    }
  } catch (e) {
    console.warn('KOI: IndexedDB write failed', e);
  }

  // Firestore write — fails silently so onboarding always completes locally
  try {
    if (uid) {
      const { doc, setDoc } = await import('firebase/firestore');
      const { firestore } = await import('./firebase');
      if (!firestore?.app) throw new Error("Firestore not properly initialized");
      await setDoc(
        doc(firestore, 'users', uid),
        {
          profile: {
            avatar: data.avatar,
            companion: data.companion,
            language: data.language,
            notificationTime: data.notificationTime,
          },
          onboarding_complete: true,
        },
        { merge: true }
      );
    }
  } catch (e) {
    console.warn('KOI: Firestore write failed, will retry on next load', e);
  }
}

export function isOnboardingComplete(): boolean {
  const win = globalThis.window;
  if (!win) return false;
  return win.localStorage.getItem('koi_onboarding_complete') === 'true';
}
