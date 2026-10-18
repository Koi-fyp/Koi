/** Advisory policy calculation only. Inputs require joint provenance review; never issues/writes pieces. */
export const REWARD_POLICY = 'koi-pakistan-25-v1-product-approved';
export type ActivitySource = 'conversation' | 'check_in' | 'breathing';
export interface CompletionCandidate {
  ownerUid: string; completionId: string; source: ActivitySource; sourceId: string;
  completedAt: string; policyVersion: string;
  evidence: { persisted: boolean; recordedUnderPolicy: boolean; explicit?: boolean; persistedExchanges?: number;
    userInitiated?: boolean; consented?: boolean; completedCycles?: number; totalCycles?: number;
    durationMs?: number; endReason?: 'completed' | 'user_stop' | 'handoff' | 'navigation'; measurement?: 'client-measured';
    cancelled: boolean; crisisInterrupted: boolean };
}
export interface RecordedAward {
  ownerUid: string; completionId: string; source: ActivitySource; completedAt: string;
}
function validDate(value: string) { return typeof value === 'string' && Number.isFinite(Date.parse(value)) && new Date(value).toISOString() === value; }
export function karachiDay(iso: string): string {
  if (!validDate(iso)) throw new Error('An exact ISO completion timestamp is required.');
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Karachi', year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(new Date(iso));
  const value = (type: Intl.DateTimeFormatPartTypes) => parts.find(part => part.type === type)!.value;
  return `${value('year')}-${value('month')}-${value('day')}`;
}
export function previewReward(ownerUid: string, candidate: CompletionCandidate, recorded: readonly RecordedAward[] | null) {
  const result = (eligible: boolean, reason: string) => ({ eligible, reason, issuanceAllowed: false as const, proposedPieces: eligible ? 1 : 0 });
  const id = (v: string) => typeof v === 'string' && !!v.trim() && v.length <= 160 && !/[\u0000-\u001f\u007f]/.test(v);
  if (!ownerUid || candidate.ownerUid !== ownerUid || !id(candidate.completionId) || !id(candidate.sourceId)
    || !['conversation','check_in','breathing'].includes(candidate.source) || candidate.policyVersion !== REWARD_POLICY || !validDate(candidate.completedAt)) return result(false, 'invalid-or-foreign-candidate');
  if (recorded === null) return result(false, 'verified-ledger-unavailable');
  if (recorded.some(r => r.ownerUid !== ownerUid || !id(r.completionId) || !['conversation','check_in','breathing'].includes(r.source) || !validDate(r.completedAt))) return result(false, 'invalid-or-foreign-ledger');
  const unique = new Set(recorded.map(r => JSON.stringify([r.source,r.completionId])));
  if (unique.size !== recorded.length || recorded.length > 25) return result(false, 'inconsistent-ledger');
  if (recorded.some(r => r.source === candidate.source && r.completionId === candidate.completionId)) return result(false, 'already-recorded');
  const e = candidate.evidence;
  if (!e || e.persisted !== true || e.recordedUnderPolicy !== true || e.cancelled !== false || e.crisisInterrupted !== false) return result(false, 'completion-not-verified');
  if (candidate.source === 'conversation' && (e.explicit !== true || !Number.isSafeInteger(e.persistedExchanges) || e.persistedExchanges! < 1)) return result(false, 'explicit-persisted-exchange-required');
  if (candidate.source === 'check_in' && (e.userInitiated !== true || e.consented !== true)) return result(false, 'saved-consented-check-in-required');
  if (candidate.source === 'breathing' && (!Number.isSafeInteger(e.completedCycles) || !Number.isSafeInteger(e.totalCycles)
    || e.totalCycles! <= 0 || e.completedCycles! < 0 || e.completedCycles! > e.totalCycles! || e.completedCycles! / e.totalCycles! < 0.8)) return result(false, 'measured-80-percent-required');
  if (recorded.length >= 25) return result(false, 'board-full');
  if (recorded.some(r => r.source === candidate.source && karachiDay(r.completedAt) === karachiDay(candidate.completedAt))) return result(false, 'daily-source-cap');
  return result(true, 'candidate-only-awaiting-provenance-and-atomic-issuance');
}
