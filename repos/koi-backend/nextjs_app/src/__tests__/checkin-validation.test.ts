import { validateCheckIn, type CheckInDraft } from '@/lib/checkins/validateCheckIn';
const scale={version:'synthetic-test-scale',min:1,max:5,step:1}; // Fixture only, not product approval.
const draft:CheckInDraft={ownerUid:'fixture-owner',entryId:'one',consent:true,occurredAt:'2026-10-18T10:00:00.000Z',ratings:{mood:3,energy:2,connection:4}};
it('accepts genuine caller-entered values only with explicit scale and consent, without persistence',()=>{
  const result=validateCheckIn(draft,'fixture-owner',scale);expect(result).toEqual(draft);expect(result.ratings).not.toBe(draft.ratings);
});
it.each([{consent:false},{ownerUid:'other'},{occurredAt:'invalid'},{ratings:{mood:NaN,energy:2,connection:4}},{ratings:{mood:6,energy:2,connection:4}},{ratings:{mood:2.5,energy:2,connection:4}}])('rejects unsafe or unsupported inputs before any writer',patch=>{
  expect(()=>validateCheckIn({...draft,...patch},'fixture-owner',scale)).toThrow('Nothing was saved');
});
