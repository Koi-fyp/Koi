/** Voluntary form validation only; no default scale/policy, writer, inference or plaintext persistence. */
export interface RatingScale { version: string; min: number; max: number; step: number; }
export interface CheckInDraft { ownerUid: string; entryId: string; consent: boolean; occurredAt: string;
  ratings: { mood: number; connection: number; energy: number }; }
export function validateCheckIn(draft: CheckInDraft, currentOwner: string, scale: RatingScale): CheckInDraft {
  const fail=():never=>{throw new Error('Check-in values or consent are invalid. Nothing was saved.');};
  if (!currentOwner || draft.ownerUid!==currentOwner || !draft.entryId?.trim() || draft.entryId.length>160 || draft.consent!==true
    || !scale.version || !Number.isFinite(scale.min)||!Number.isFinite(scale.max)||!Number.isFinite(scale.step)||scale.min>=scale.max||scale.step<=0
    || !Number.isFinite(Date.parse(draft.occurredAt)))return fail();
  for(const value of Object.values(draft.ratings)) {
    const ticks=(value-scale.min)/scale.step;
    if(!Number.isFinite(value)||value<scale.min||value>scale.max||Math.abs(ticks-Math.round(ticks))>1e-8)return fail();
  }
  if(Object.keys(draft.ratings).sort().join(',')!=='connection,energy,mood')return fail();
  return {...draft,ratings:{...draft.ratings}};
}
