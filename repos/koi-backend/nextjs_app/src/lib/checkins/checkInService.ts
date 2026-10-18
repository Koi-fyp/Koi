import { auth } from '@/lib/firebase';
import { decrypt, encrypt, getActiveCryptoContext } from '@/lib/crypto';
import { activityLedger } from '@/lib/activities/activityLedger';
import { REWARD_POLICY } from '@/lib/activities/rewardPreview';
import { validateCheckIn, type CheckInDraft } from './validateCheckIn';

export const CHECK_IN_SCALE = { version: 'koi-dcw9-1-5-v1', min: 1, max: 5, step: 1 } as const;
export class CheckInError extends Error {
  constructor(readonly reason: 'locked' | 'owner-changed' | 'unreadable') { super(`Check-in ${reason}.`); }
}
const ownerGuard = (uid: string) => { if (!uid || auth?.currentUser?.uid !== uid) throw new CheckInError('owner-changed'); };
/** Reuse the existing cache-hit crypto path only. Never initialize a new key/salt to read ratings.
 * Linked sessions require their existing unlock provider, which AuthContext does not expose yet.
 */
async function existingContext(uid: string) {
  ownerGuard(uid);
  try {
    if (!auth!.currentUser!.isAnonymous || !localStorage.getItem('koi_anon_secret') || !localStorage.getItem(`koi_salt_cache_${uid}`)) throw new CheckInError('locked');
    const context = await getActiveCryptoContext(uid, { isLinked: false });
    ownerGuard(uid);
    return context;
  } catch (error) { if (error instanceof CheckInError) throw error; throw new CheckInError('locked'); }
}
export async function checkInAvailable(uid: string) { await existingContext(uid); }
export async function saveCheckIn(draft: CheckInDraft) {
  ownerGuard(draft.ownerUid);
  const valid = validateCheckIn(draft, draft.ownerUid, CHECK_IN_SCALE);
  const context = await existingContext(valid.ownerUid);
  const payload = await encrypt(JSON.stringify({ scale_version: CHECK_IN_SCALE.version, ...valid.ratings }), context.secret, context.saltB64);
  ownerGuard(valid.ownerUid);
  return activityLedger.record({ ownerUid: valid.ownerUid, completionId: valid.entryId, source: 'check_in', sourceId: valid.entryId,
    completedAt: new Date(Date.now()).toISOString(), policyVersion: REWARD_POLICY,
    evidence: { persisted: true, recordedUnderPolicy: true, userInitiated: true, consented: true, cancelled: false, crisisInterrupted: false } }, payload);
}
export interface SavedCheckIn { id: string; completedAt: string; mood: number; connection: number; energy: number; }
export async function readCheckIns(uid: string): Promise<{ entries: SavedCheckIn[]; unreadable: number }> {
  const state = await activityLedger.read(uid);
  const events = state.events.filter(event => event.source_type === 'check_in');
  if (!events.length) return { entries: [], unreadable: 0 };
  const context = await existingContext(uid);
  const entries: SavedCheckIn[] = []; let unreadable = 0;
  for (const event of events) {
    ownerGuard(uid);
    try {
      const decoded = JSON.parse(await decrypt(event.payload!, context.secret));
      ownerGuard(uid);
      if (decoded.scale_version !== CHECK_IN_SCALE.version || Object.keys(decoded).sort().join(',') !== 'connection,energy,mood,scale_version') throw new Error('invalid');
      const { mood, connection, energy } = decoded;
      validateCheckIn({ ownerUid: uid, entryId: event.id, occurredAt: event.completed_at, consent: true, ratings: { mood, connection, energy } }, uid, CHECK_IN_SCALE);
      entries.push({ id: event.id, completedAt: event.completed_at, mood, connection, energy });
    } catch (error) { if (error instanceof CheckInError && error.reason === 'owner-changed') throw error; unreadable++; }
  }
  ownerGuard(uid);
  return { entries: entries.sort((a, b) => a.completedAt.localeCompare(b.completedAt)), unreadable };
}
