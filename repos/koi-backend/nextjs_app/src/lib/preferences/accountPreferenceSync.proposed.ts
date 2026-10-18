/** Owner-authorized preference adapter. Merge-only profile writes; no crypto or auth changes. */
import { doc, getDocFromServer, setDoc } from 'firebase/firestore';
import { auth, firestore } from '@/lib/firebase';
import { validTime } from './userPreferences';

export interface AccountPreferenceFields {
  avatar?: 'female_human' | 'male_human' | 'fox'; companion?: 'aisha' | 'raza' | 'koi';
  language?: 'en' | 'ur'; notificationTime?: string;
}
export class AccountPreferenceSyncError extends Error {
  constructor(readonly reason: 'owner-changed'|'cancelled'|'configuration'|'invalid-profile'|'permission-denied'|'unauthenticated'|'unavailable'|'unknown') {
    super(`Account preference sync failed: ${reason}.`);
  }
}
const guard = (ownerUid: string, signal: AbortSignal) => {
  if (signal.aborted) throw new AccountPreferenceSyncError('cancelled');
  if (!auth || !firestore || auth.app !== firestore.app) throw new AccountPreferenceSyncError('configuration');
  if (!ownerUid || ownerUid.length > 128 || auth.currentUser?.uid !== ownerUid) throw new AccountPreferenceSyncError('owner-changed');
  if (/[\/\u0000-\u001f\u007f]/.test(ownerUid)) throw new AccountPreferenceSyncError('configuration');
};
function profileFields(input: unknown, writing: boolean): AccountPreferenceFields {
  const invalid = (): never => { throw new AccountPreferenceSyncError('invalid-profile'); };
  if (!input || typeof input !== 'object' || Array.isArray(input)) return invalid();
  const source = input as Record<string,unknown>, fields: AccountPreferenceFields = {};
  const keys = ['avatar','companion','language','notificationTime'];
  if (writing && Object.keys(source).some(k => !keys.includes(k))) return invalid();
  if (source.avatar !== undefined) {
    if (!['female_human','male_human','fox'].includes(source.avatar as string)) return invalid();
    fields.avatar = source.avatar as AccountPreferenceFields['avatar'];
  }
  if (source.companion !== undefined) {
    if (!['aisha','raza','koi'].includes(source.companion as string)) return invalid();
    fields.companion = source.companion as AccountPreferenceFields['companion'];
  }
  const pairs = {aisha:'female_human',raza:'male_human',koi:'fox'} as const;
  if (fields.avatar && fields.companion && pairs[fields.companion] !== fields.avatar) return invalid();
  // Reading legacy avatar-only profiles is allowed; never silently rewrite/adopt them.
  if (writing && (!!fields.avatar !== !!fields.companion)) return invalid();
  if (source.language !== undefined) {
    if (source.language !== 'en' && source.language !== 'ur') return invalid();
    fields.language = source.language;
  }
  if (source.notificationTime !== undefined) {
    if (!validTime(source.notificationTime)) return invalid();
    fields.notificationTime = source.notificationTime as string;
  }
  if (!Object.keys(fields).length) return invalid();
  return fields;
}
function safeError(error: unknown): AccountPreferenceSyncError {
  if (error instanceof AccountPreferenceSyncError) return error;
  const code = error && typeof error === 'object' && 'code' in error ? error.code : null;
  return new AccountPreferenceSyncError(code === 'permission-denied' ? 'permission-denied' : code === 'unauthenticated' ? 'unauthenticated' : code === 'unavailable' || code === 'deadline-exceeded' ? 'unavailable' : 'unknown');
}
export async function readOwnedAccountPreferences(ownerUid: string, signal: AbortSignal) {
  guard(ownerUid,signal);
  try {
    const snapshot = await getDocFromServer(doc(firestore!,'users',ownerUid));
    guard(ownerUid,signal);
    if (!snapshot.exists()) return {status:'missing' as const,ownerUid};
    const profile = snapshot.data().profile;
    if (profile === undefined) return {status:'no-profile' as const,ownerUid};
    return {status:'server-read' as const,ownerUid,preferences:profileFields(profile,false)};
  } catch (error) { throw safeError(error); }
}
export async function writeOwnedAccountPreferences(ownerUid: string, input: AccountPreferenceFields, signal: AbortSignal) {
  guard(ownerUid,signal);
  const fields = profileFields(input,true);
  try {
    // Existing document shape. Merge writes only supplied profile leaves, not crypto/safety fields.
    await setDoc(doc(firestore!,'users',ownerUid),{profile:fields},{merge:true});
    guard(ownerUid,signal);
    return {status:'server-acknowledged' as const,ownerUid,fields:Object.keys(fields)};
  } catch (error) { throw safeError(error); }
}
