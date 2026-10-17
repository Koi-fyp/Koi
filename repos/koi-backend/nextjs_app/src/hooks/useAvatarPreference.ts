import { useUserPreferences } from '@/hooks/useUserPreferences';
import { resolveAvatarPreference, type ResolvedAvatarPreference } from '@/lib/avatar/avatarPreference';
import type { UserPreferences } from '@/lib/preferences/userPreferences';
export type AvatarPreferenceState =
  | { status: 'loading' }
  | { status: 'ready'; uid: string | null; preference: ResolvedAvatarPreference; profile: UserPreferences | null }
  | { status: 'error'; uid: string };
export function useAvatarPreference(uid: string | undefined, authLoading: boolean): AvatarPreferenceState {
  const { state } = useUserPreferences(uid, authLoading);
  return state.status === 'ready' ? { ...state, preference: resolveAvatarPreference(state.profile) } : state;
}
