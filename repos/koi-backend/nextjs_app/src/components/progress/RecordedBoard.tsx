'use client';
import { useState } from 'react';
export interface RecordedPiece { ownerUid: string; slot: number; completionId: string; source: 'conversation'|'check_in'|'breathing'; unlockedAt: string; }
/** Presentation of supplied recorded pieces only. Never calculates or issues a reward. */
export default function RecordedBoard({ ownerUid, pieces, legacyTotal }: { ownerUid: string; pieces: readonly RecordedPiece[] | null; legacyTotal?: number }) {
  const [selection, select] = useState<{owner:string;slot:number}|null>(null);
  const seenSlots=new Set<number>(),seenEvents=new Set<string>();
  const valid=pieces!==null&&pieces.length<=25&&pieces.every(p=> {
    const event=JSON.stringify([p.source,p.completionId]);
    if(p.ownerUid!==ownerUid||!Number.isInteger(p.slot)||p.slot<0||p.slot>=25||!p.completionId
      ||!['conversation','check_in','breathing'].includes(p.source)||!Number.isFinite(Date.parse(p.unlockedAt))||seenSlots.has(p.slot)||seenEvents.has(event))return false;
    seenSlots.add(p.slot);seenEvents.add(event);return true;
  });
  const current=selection?.owner===ownerUid?selection.slot:null;
  const saved=valid?pieces!:[];
  const detail=saved.find(p=>p.slot===current);
  return <section className="neo-card p-5" aria-label="Recorded 25-piece board">
    <h2 className="font-bold text-xl mb-2">Recorded puzzle board</h2>
    {Number.isSafeInteger(legacyTotal)&&legacyTotal!>=0&&<p>Legacy recorded total: {legacyTotal}. Not converted into board unlocks.</p>}
    {!valid?<p role="status">Recorded piece events are unavailable or unverified. No unlocks are inferred.</p>
      :<p role="status">{saved.length} of 25 recorded slots. Pieces are not a measure of mental-health improvement.</p>}
    <div className="grid grid-cols-5 gap-2 my-4" aria-label="Puzzle slots">{Array.from({length:25},(_,slot)=>{
      const piece=saved.find(p=>p.slot===slot);
      return <button key={slot} type="button" className={`border-2 border-black rounded-lg p-3 ${piece?'bg-[var(--neo-yellow)]':'bg-white'}`}
        aria-label={`Slot ${slot+1}: ${piece?'recorded unlock':valid?'not unlocked':'status unavailable'}`}
        aria-pressed={current===slot} onClick={()=>select({owner:ownerUid,slot})}>{slot+1}</button>;
    })}</div>
    {current!==null&&<div aria-live="polite"><h3 className="font-bold">Slot {current+1}</h3>
      <p>{detail?`Recorded ${detail.source} completion · ${new Date(detail.unlockedAt).toLocaleString()}`:valid?'No recorded unlock for this slot.':'No verified piece event source is connected.'}</p></div>}
    <p className="text-sm">Policy proposal: one 25-slot board; thresholds 5, 10, 15, 20, 25. No milestone unlock or reward is issued here. Joint approval and persisted completion provenance are required.</p>
  </section>;
}
