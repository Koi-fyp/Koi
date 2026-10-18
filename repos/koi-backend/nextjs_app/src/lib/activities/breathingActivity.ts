import { auth } from '@/lib/firebase';
import { activityLedger } from './activityLedger';
import { REWARD_POLICY } from './rewardPreview';
export interface BreathingResult {
  sessionId: string; startedAt: string; endedAt: string; cyclesPlanned: number; cyclesCompleted: number;
  endReason: 'completed' | 'user_stop' | 'handoff' | 'navigation';
  /** Active monotonic duration, excluding pauses. Client-measured, not signed backend proof. */
  durationMs: number;
}
export function breathingEligible(result: BreathingResult) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(result.sessionId)
    && Number.isFinite(Date.parse(result.startedAt)) && Number.isFinite(Date.parse(result.endedAt))
    && Number.isSafeInteger(result.cyclesPlanned) && result.cyclesPlanned > 0
    && Number.isSafeInteger(result.cyclesCompleted) && result.cyclesCompleted <= result.cyclesPlanned
    && result.cyclesCompleted >= Math.ceil(0.8 * result.cyclesPlanned)
    && result.endReason === 'completed' && Number.isFinite(result.durationMs) && result.durationMs >= 48000;
}
export async function completionHash(input: string) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input));
  return Array.from(new Uint8Array(digest), value => value.toString(16).padStart(2, '0')).join('');
}
export async function saveBreathingResult(uid: string, result: BreathingResult) {
  if (auth?.currentUser?.uid !== uid) throw new Error('Activity owner changed.');
  if (!breathingEligible(result)) return { outcome: 'ineligible' as const };
  const completionId = await completionHash(`koi:breathing:v1:${uid}:${result.sessionId}`);
  if (auth?.currentUser?.uid !== uid) throw new Error('Activity owner changed.');
  return activityLedger.record({ ownerUid: uid, completionId, source: 'breathing', sourceId: result.sessionId,
    completedAt: result.endedAt, policyVersion: REWARD_POLICY,
    evidence: { persisted: true, recordedUnderPolicy: true, cancelled: false, crisisInterrupted: false,
      completedCycles: result.cyclesCompleted, totalCycles: result.cyclesPlanned, durationMs: result.durationMs,
      endReason: result.endReason, measurement: 'client-measured' } }, null);
}
