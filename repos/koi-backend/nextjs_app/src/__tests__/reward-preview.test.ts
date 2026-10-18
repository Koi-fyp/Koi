import { previewReward, karachiDay, REWARD_POLICY, type CompletionCandidate, type RecordedAward } from '@/lib/activities/rewardPreview';
const candidate: CompletionCandidate = { ownerUid:'synthetic-owner',completionId:'completion-a',source:'conversation',sourceId:'session-a',completedAt:'2026-10-18T19:00:00.000Z',policyVersion:REWARD_POLICY,
  evidence:{persisted:true,recordedUnderPolicy:true,explicit:true,persistedExchanges:1,cancelled:false,crisisInterrupted:false} };
const preview=(patch:Partial<CompletionCandidate>={},ledger:RecordedAward[]|null=[])=>previewReward('synthetic-owner',{...candidate,...patch},ledger);
it('never authorizes issuance even for a candidate that meets product rules',()=>{
  expect(preview()).toMatchObject({eligible:true,proposedPieces:1,issuanceAllowed:false});
});
it.each([{explicit:false},{persisted:false},{recordedUnderPolicy:false},{persistedExchanges:0},{cancelled:true},{crisisInterrupted:true}])('rejects incomplete, historical, failed, navigation-only or crisis-interrupted candidates',patch=>{
  expect(preview({evidence:{...candidate.evidence,...patch}}).eligible).toBe(false);
});
it('requires verified ledger availability and preserves foreign and legacy records without conversion',()=>{
  expect(preview({},null).reason).toBe('verified-ledger-unavailable');
  const ledger=[{ownerUid:'other',completionId:'old',source:'check_in' as const,completedAt:candidate.completedAt}];
  const before=JSON.stringify(ledger);expect(preview({},ledger).eligible).toBe(false);expect(JSON.stringify(ledger)).toBe(before);
});
it('rejects replay, daily same-source cap and full boards; a different activity has its own cap',()=>{
  const record:RecordedAward={ownerUid:candidate.ownerUid,completionId:candidate.completionId,source:'conversation',completedAt:candidate.completedAt};
  expect(preview({},[record]).reason).toBe('already-recorded');
  expect(preview({},[{...record,completionId:'other'}]).reason).toBe('daily-source-cap');
  expect(preview({source:'check_in',evidence:{...candidate.evidence,userInitiated:true,consented:true}},[record]).eligible).toBe(true);
  expect(preview({},Array.from({length:25},(_,i)=>({...record,completionId:String(i)}))).reason).toBe('board-full');
});
it('uses Asia/Karachi midnight rather than UTC/local device day',()=>{
  expect(karachiDay('2026-10-18T18:59:59.000Z')).not.toBe(karachiDay('2026-10-18T19:00:00.000Z'));
});
it.each([[4,false],[5,true],[6,true],[7,false]])('requires measured breathing cycles: %i of six', (cycles,eligible)=>{
  expect(preview({source:'breathing',evidence:{...candidate.evidence,completedCycles:cycles as number,totalCycles:6}}).eligible).toBe(eligible);
});
it('notification preferences and unconsented/unsaved check-ins cannot qualify',()=>{
  expect(preview({source:'check_in'}).eligible).toBe(false);
  expect(preview({source:'check_in',evidence:{...candidate.evidence,userInitiated:true,consented:false}}).eligible).toBe(false);
});
