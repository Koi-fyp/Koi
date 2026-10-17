import type { UserRecord } from '@/lib/db';
import { loadUserPreferences, saveUserPreferences, notifyPreferencesChanged, PREFERENCES_CHANGED } from '@/lib/preferences/userPreferences';

export type CompanionId = 'aisha' | 'raza' | 'koi';
export type AvatarId = 'female_human' | 'male_human' | 'fox';

export type ResolvedAvatarPreference = (
  | { status: 'selected'; companion: 'aisha'; avatar: 'female_human'; name: 'Aisha'; imageSrc: '/Female.png'; modelUrl: '/models/koi-female.vrm' }
  | { status: 'selected'; companion: 'raza'; avatar: 'male_human'; name: 'Raza'; imageSrc: '/Male.png'; modelUrl: '/models/koi-male.vrm' }
  | { status: 'selected'; companion: 'koi'; avatar: 'fox'; name: 'Koi'; imageSrc: null; modelUrl: null }
  | { status: 'unselected' }) & { displayName?: string };

const BY_COMPANION: Record<CompanionId, ResolvedAvatarPreference> = {
  aisha: { status: 'selected', companion: 'aisha', avatar: 'female_human', name: 'Aisha', imageSrc: '/Female.png', modelUrl: '/models/koi-female.vrm' },
  raza: { status: 'selected', companion: 'raza', avatar: 'male_human', name: 'Raza', imageSrc: '/Male.png', modelUrl: '/models/koi-male.vrm' },
  koi: { status: 'selected', companion: 'koi', avatar: 'fox', name: 'Koi', imageSrc: null, modelUrl: null },
};

/** Companion selection is canonical for new profiles. Avatar-only legacy profiles remain supported. */
function resolveRepresentation(profile?: Pick<UserRecord, 'companion' | 'avatar'> | null): ResolvedAvatarPreference {
  if (profile?.companion === 'aisha') return BY_COMPANION.aisha;
  if (profile?.companion === 'raza') return BY_COMPANION.raza;
  if (profile?.companion === 'koi') return BY_COMPANION.koi;
  if (profile?.avatar === 'female_human') return BY_COMPANION.aisha;
  if (profile?.avatar === 'male_human') return BY_COMPANION.raza;
  if (profile?.avatar === 'fox') return BY_COMPANION.koi;
  return { status: 'unselected' };
}

export function resolveAvatarPreference(profile?: (Pick<UserRecord, 'companion' | 'avatar'> & { displayName?: string }) | null): ResolvedAvatarPreference {
  const resolved = resolveRepresentation(profile);
  const displayName = typeof profile?.displayName === 'string' ? profile.displayName.trim() : '';
  return resolved.status === 'selected' && displayName && [...displayName].length <= 64 && !/[\u0000-\u001f\u007f]/.test(displayName) ? { ...resolved, displayName } : resolved;
}

export async function loadAvatarPreference(uid: string): Promise<ResolvedAvatarPreference> {
  return resolveAvatarPreference(await loadUserPreferences(uid));
}

/** Explicit choice only; the common writer preserves other profile fields. */
export async function saveAvatarPreference(uid: string, companion: CompanionId, displayName?: string): Promise<void> {
  if (!Object.hasOwn(BY_COMPANION, companion)) throw new Error('Choose a valid companion.');
  const selection = BY_COMPANION[companion];
  if (selection.status !== 'selected') throw new Error('Choose a companion.');
  await saveUserPreferences(uid, { companion, avatar: selection.avatar, ...(displayName !== undefined ? { displayName } : {}) });
}
export const AVATAR_PREFERENCE_CHANGED = PREFERENCES_CHANGED;
export const notifyAvatarPreferenceChanged = notifyPreferencesChanged;
