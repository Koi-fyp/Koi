'use client';
import { useId, useRef, useState } from 'react';
import { useModalFocus } from '@/hooks/useModalFocus';
export interface RecordedPiece { ownerUid: string; slot: number; completionId: string; source: 'conversation'|'check_in'|'breathing'; unlockedAt: string; provenance?: string; }
/** Presentation of supplied recorded pieces only. Never calculates or issues a reward. */
export default function RecordedBoard({ ownerUid, pieces, legacyTotal, milestones = [] }: { ownerUid: string; pieces: readonly RecordedPiece[] | null; legacyTotal?: number; milestones?: readonly number[] }) {
  const [selection, select] = useState<{owner:string;slot:number}|null>(null);
  const [milestone, selectMilestone] = useState<{owner:string;threshold:number}|null>(null);
  const dialog = useRef<HTMLDivElement>(null), title = useId();
  const threshold = milestone?.owner === ownerUid ? milestone.threshold : null;
  const close = () => { select(null); selectMilestone(null); };
  useModalFocus(selection?.owner === ownerUid || threshold !== null, dialog, close);
  const seenSlots=new Set<number>(),seenEvents=new Set<string>();
  const valid=pieces!==null&&pieces.length<=25&&pieces.every(p=> {
    const event=JSON.stringify([p.source,p.completionId]);
    if(p.ownerUid!==ownerUid||!Number.isInteger(p.slot)||p.slot<0||p.slot>=25||!p.completionId
      ||!['conversation','check_in','breathing'].includes(p.source)||!Number.isFinite(Date.parse(p.unlockedAt))||seenSlots.has(p.slot)||seenEvents.has(event))return false;
    seenSlots.add(p.slot);seenEvents.add(event);return true;
  });
  const current=selection?.owner===ownerUid?selection.slot:null;
  const saved=valid?pieces!:[];
  const unlockedMilestones = milestones.filter(value => [5, 10, 15, 20, 25].includes(value) && value <= saved.length);
  const milestoneItems = [5, 10, 15, 20, 25].map((value, index) => ({
    id: value, title: `${value} pieces`, done: unlockedMilestones.includes(value),
    color: ['#2DD36F', '#2D63EB', '#FFD100', '#845EC2', '#2DD36F'][index],
    desc: !valid ? 'Milestone status is unavailable.' : unlockedMilestones.includes(value) ? 'Unlocked by a saved milestone receipt.' : 'No saved milestone receipt yet.',
    reward: 'Unlocked',
  }));
  const detail=saved.find(p=>p.slot===current);
  return <section className="neo-card p-5 mb-5" aria-label="Recorded 25-piece board">
    <h2 className="font-extrabold text-[1.1rem] tracking-[-0.02em] text-black mb-2">Recorded puzzle board</h2>
    {Number.isSafeInteger(legacyTotal)&&legacyTotal!>=0&&<p>Legacy recorded total: {legacyTotal}. Not converted into board unlocks.</p>}
    {!valid?<p role="status">Recorded piece events are unavailable or unverified. No unlocks are inferred.</p>
      :<p role="status">{saved.length} of 25 recorded slots. Pieces are not a measure of mental-health improvement.</p>}
    <div className="grid grid-cols-5 gap-2 my-4" aria-label="Puzzle slots">{Array.from({length:25},(_,slot)=>{
      const piece=saved.find(p=>p.slot===slot);
      return <button key={slot} type="button" className={`border-2 border-black rounded-xl py-3 font-bold shadow-[2px_2px_0_0_#000] ${piece?'bg-[var(--neo-yellow)]':'bg-white'}`}
        aria-label={`Slot ${slot+1}: ${piece?'recorded unlock':valid?'not unlocked':'status unavailable'}`}
        aria-pressed={current===slot} onClick={()=>select({owner:ownerUid,slot})}>{slot+1}</button>;
    })}</div>
    <div className="koi-action-row my-3" aria-label="Milestone thresholds">{[5,10,15,20,25].map(n => <button type="button" className="neo-btn-secondary neo-btn-sm" key={n}
      onClick={() => { select(null); selectMilestone({owner:ownerUid,threshold:n}); }} aria-label={`Milestone ${n}: ${!valid?'status unavailable':unlockedMilestones.includes(n)?'recorded milestone unlocked':'not unlocked'}`}>{n} pieces</button>)}</div>
      {/* Existing timeline, now driven only by saved milestone receipts. */}
      <div
        style={{
          background: '#fff',
          border: '2.5px solid #000',
          borderRadius: '1.25rem',
          boxShadow: '6px 6px 0 0 #000',
          padding: '1.25rem',
          margin: '0.75rem 0 1.25rem',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '1.1rem' }}>
          <h2
            style={{
              fontFamily: 'var(--font-body)',
              fontWeight: 800,
              fontSize: '1.1rem',
              color: '#000',
              letterSpacing: '-0.02em',
            }}
          >
            Milestones
          </h2>
          <div
            style={{
              background: '#FFD100',
              border: '2px solid #000',
              borderRadius: '12px',
              padding: '0.25rem 0.625rem',
              fontSize: '0.7rem',
              fontWeight: 700,
              boxShadow: '2px 2px 0 #000',
            }}
          >
            {valid ? `${unlockedMilestones.length} of 5 unlocked` : 'Unavailable'}
          </div>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '0.875rem' }}>
          {milestoneItems.map((m, i) => (
            <div
              key={m.id}
              role="button" tabIndex={0} aria-pressed={threshold === m.id} aria-label={`Milestone timeline ${m.id}: ${!valid ? 'unavailable' : m.done ? 'unlocked' : 'locked'}`} onKeyDown={event => { if (event.target === event.currentTarget && (event.key === 'Enter' || event.key === ' ')) { event.preventDefault(); event.currentTarget.click(); } }}
              style={{
                display: 'flex',
                gap: '0.875rem',
                alignItems: 'flex-start',
                opacity: m.done ? 1 : 0.6,
                cursor: 'pointer',
                padding: '0.625rem',
                margin: '-0.625rem',
                borderRadius: '0.75rem',
                transition: 'all 0.2s ease',
                background: threshold === m.id ? 'rgba(0,0,0,0.04)' : 'transparent',
                border: threshold === m.id ? '2px solid rgba(0,0,0,0.06)' : '2px solid transparent',
              }}
              onClick={() => { select(null); selectMilestone({owner: ownerUid, threshold: m.id}); }}
              onMouseEnter={(e) => {
                if (threshold !== m.id) {
                  e.currentTarget.style.background = 'rgba(0,0,0,0.02)';
                }
              }}
              onMouseLeave={(e) => {
                if (threshold !== m.id) {
                  e.currentTarget.style.background = 'transparent';
                }
              }}
            >
              <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', flexShrink: 0, paddingTop: '2px' }}>
                <div
                  style={{
                    width: '24px',
                    height: '24px',
                    borderRadius: '6px',
                    background: m.done ? m.color : '#eee',
                    border: '2px solid #000',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    flexShrink: 0,
                    transition: 'all 0.2s ease',
                    transform: threshold === m.id ? 'scale(1.15)' : 'scale(1)',
                    boxShadow: m.done ? '2px 2px 0 #000' : 'none',
                  }}
                >
                  {m.done ? (
                    <span aria-hidden="true">&#10003;</span>
                  ) : (
                    <div style={{ width: '8px', height: '8px', borderRadius: '50%', background: '#bbb' }} />
                  )}
                </div>
                {i < milestoneItems.length - 1 && (
                  <div
                    style={{
                      width: '2px',
                      flex: '1 0 20px',
                      background: m.done ? 'rgba(0,0,0,0.15)' : '#eee',
                      marginTop: '4px',
                    }}
                  />
                )}
              </div>
              <div style={{ flex: 1 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '3px' }}>
                  <p style={{ fontFamily: 'var(--font-body)', fontWeight: 700, fontSize: '0.875rem', color: '#000' }}>
                    {m.title}
                  </p>
                  {m.done && (
                    <span
                      style={{
                        background: m.color,
                        border: '1.5px solid #000',
                        borderRadius: '6px',
                        padding: '0.125rem 0.375rem',
                        fontSize: '0.625rem',
                        fontWeight: 700,
                        color: '#000',
                      }}
                    >
                      {m.reward}
                    </span>
                  )}
                </div>
                <p style={{ fontFamily: 'var(--font-body)', fontSize: '0.78rem', color: '#777', lineHeight: 1.5 }}>
                  {m.desc}
                </p>
              </div>
            </div>
          ))}
        </div>
      </div>

    {(current!==null || threshold!==null)&&<div className="fixed inset-0 z-50 bg-black/60 p-4 flex items-center justify-center" onClick={e=>{if(e.target===e.currentTarget)close();}}>
      <div ref={dialog} role="dialog" aria-modal="true" aria-labelledby={title} tabIndex={-1} className="neo-card bg-white p-5 max-w-md w-full">
        <h3 id={title} className="font-bold">{threshold!==null?`Milestone: ${threshold} pieces`:`Slot ${current!+1}`}</h3>
        {threshold!==null?<p>{!valid?'No verified piece event source is connected.':unlockedMilestones.includes(threshold)?`Milestone ${threshold} is permanently unlocked by a saved milestone receipt.`:'No saved milestone receipt for this threshold.'}</p>
          :<p>{detail?`Recorded ${detail.source} completion · ${new Date(detail.unlockedAt).toLocaleString()} | ${detail.provenance ?? 'recorded activity'}`:valid?'No recorded unlock for this slot.':'No verified piece event source is connected.'}</p>}
        <button type="button" className="neo-btn-primary neo-btn-sm mt-3" onClick={close}>Close details</button>
      </div></div>}
    <p className="text-sm">One 25-slot board; milestones at 5, 10, 15, 20, 25. Only saved reward receipts unlock pieces. Daily caps use the device clock in Asia/Karachi.</p>
  </section>;
}
