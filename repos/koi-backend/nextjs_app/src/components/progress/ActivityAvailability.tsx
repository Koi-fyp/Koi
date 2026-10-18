'use client';
import { useEffect, useRef, useState, type FormEvent } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { auth } from '@/lib/firebase';
import { useActivityData } from '@/hooks/useActivityData';
import { checkInAvailable, saveCheckIn } from '@/lib/checkins/checkInService';
import RecordedBoard from './RecordedBoard';
import CheckInChart from './CheckInChart';
import ActivityHeatmap from './ActivityHeatmap';
import { RANGES, activityDayCounts, dashboardCounts, filterCheckIns, rangeStart, type RangeKey } from '@/lib/progress/dashboardModel';

interface Totals { completedExchanges: number; conversations: number }
export default function ActivityAvailability({ legacyTotal, totals }: { legacyTotal?: number; totals?: Totals }) {
  const { user } = useAuth();
  return user ? <OwnedActivities key={user.uid} uid={user.uid} legacyTotal={legacyTotal} totals={totals} /> : null;
}
const COUNT_LABELS = [
  ['completedExchanges', 'Completed exchanges'], ['conversations', 'Conversations with replies'], ['completedConversations', 'Completed conversations'],
  ['checkIns', 'Check-ins'], ['breathingSessions', 'Breathing sessions'], ['pieces', 'Earned pieces'], ['milestones', 'Milestones'],
] as const;
function OwnedActivities({ uid, legacyTotal, totals }: { uid: string; legacyTotal?: number; totals?: Totals }) {
  const data = useActivityData(uid);
  const [range, setRange] = useState<RangeKey>('30d');
  const now = Date.now();
  const [entry, setEntry] = useState(() => crypto.randomUUID());
  const attemptTime = useRef<string | null>(null);
  const [ratings, setRatings] = useState({ mood: '', connection: '', energy: '' });
  const [consent, setConsent] = useState(false);
  const [available, setAvailable] = useState(false);
  const [notice, setNotice] = useState('Checking encrypted storage…');
  const [saving, setSaving] = useState(false), [saved, setSaved] = useState(false);
  const busy = useRef(false);
  const checkAccess = () => {
    setAvailable(false);
    void checkInAvailable(uid).then(() => { if (auth?.currentUser?.uid === uid) { setAvailable(true); setNotice('Ratings are encrypted on this device. Saving is voluntary.'); } })
      .catch(() => { if (auth?.currentUser?.uid === uid) setNotice('Check-in is locked. Unlock your existing account key before saving.'); });
  };
  useEffect(checkAccess, [uid]);
  const save = async (event: FormEvent) => {
    event.preventDefault();
    if (busy.current || saved || !available) return;
    busy.current = true; setSaving(true);
    try {
      if (Object.values(ratings).some(value => !value)) throw new Error('missing');
      const result = await saveCheckIn({ ownerUid: uid, entryId: entry, occurredAt: attemptTime.current ?? (attemptTime.current = new Date().toISOString()), consent,
        ratings: { mood: Number(ratings.mood), connection: Number(ratings.connection), energy: Number(ratings.energy) } });
      if (auth?.currentUser?.uid !== uid) return;
      setSaved(true); setRatings({ mood: '', connection: '', energy: '' }); setConsent(false);
      setNotice(result.outcome === 'awarded' ? 'Check-in saved encrypted. One puzzle piece earned.' : 'Check-in saved encrypted. No additional piece: the daily limit or full board applies, or this save was already recorded.');
    } catch { if (auth?.currentUser?.uid === uid) setNotice('Check-in was not confirmed saved. Check consent, all three ratings (1–5) and key/storage access, then retry.'); }
    finally { busy.current = false; setSaving(false); }
  };
  const ready = data.status === 'ready' ? data : null;
  const counts = ready ? dashboardCounts({ completedExchanges: totals?.completedExchanges ?? NaN, conversations: totals?.conversations ?? NaN,
    events: ready.ledger.events, rewards: ready.ledger.rewards, milestones: ready.ledger.milestones }) : null;
  return <>
    <section className="neo-card p-5 my-5" aria-label="Recorded activities">
      <h2 className="font-bold text-xl">Check-ins and activities</h2>
      <p className="my-3">Voluntary check-in: Mood, Connection and Energy, each from 1 to 5. Ratings describe your own experience; they are not a diagnosis.</p>
      <form onSubmit={save}>
        <fieldset disabled={!available || saving || saved}>
          <legend className="font-bold">Voluntary check-in</legend>
          {(['mood', 'connection', 'energy'] as const).map(name => <label className="block my-3" key={name}>
            {name[0].toUpperCase() + name.slice(1)}
            <select required aria-label={name[0].toUpperCase() + name.slice(1)} value={ratings[name]} onChange={event => setRatings(previous => ({ ...previous, [name]: event.target.value }))} className="border-2 border-black rounded-lg p-2 ml-3">
              <option value="">Choose rating</option>{[1, 2, 3, 4, 5].map(value => <option key={value} value={value}>{value}</option>)}
            </select>
          </label>)}
          <label className="block my-3"><input required type="checkbox" checked={consent} onChange={event => setConsent(event.target.checked)} /> I consent to saving my check-in encrypted on this device.</label>
          <button type="submit" className="neo-btn-ghost">{saving ? 'Saving check-in…' : saved ? 'Check-in saved' : 'Save check-in'}</button>
        </fieldset>
      </form>
      <p role="status" className="text-sm my-3">{notice}</p>
      {!available && <button type="button" onClick={checkAccess}>Retry key access</button>}
      {saved && <button type="button" className="neo-btn-ghost" onClick={() => { setEntry(crypto.randomUUID()); attemptTime.current = null; setSaved(false); setNotice('A new check-in is ready. Only one check-in piece can be earned per Karachi day.'); }}>Record another check-in</button>}
      {data.status === 'error' && <p role="alert">Saved activities could not be loaded. Your records have not been changed.</p>}
      <h3 className="font-bold mt-4">Your saved activity</h3>
      <dl className="text-sm grid grid-cols-2 gap-2 my-3">{COUNT_LABELS.map(([key, label]) => <div key={key} className="border-2 border-black rounded-lg p-2">
        <dt className="font-bold">{label}</dt>
        <dd>{counts && Number.isFinite(counts[key]) ? (key === 'pieces' ? `${counts.pieces} of 25` : counts[key]) : data.status === 'error' || counts ? 'Unavailable' : 'Loading…'}</dd>
      </div>)}</dl>
      <h3 className="font-bold mt-4">Check-in ratings over time</h3>
      <div role="group" aria-label="Time range" className="flex flex-wrap gap-2 my-2">{RANGES.map(option => <button key={option.key} type="button" aria-pressed={range === option.key}
        className={`border-2 border-black rounded-lg px-3 py-1 text-sm ${range === option.key ? 'bg-black text-white' : 'bg-white'}`} onClick={() => setRange(option.key)}>{option.label}</button>)}</div>
      {data.status === 'error' ? <p>Saved rating history is unavailable.</p> : !ready ? <p>Loading saved ratings...</p> : ready.locked ? <p>Saved ratings are locked. Unlock the existing key to view them.</p>
        : <CheckInChart key={range} entries={filterCheckIns(ready.entries, range, now)} from={rangeStart(range, now)} to={now} title={`Check-in ratings, ${RANGES.find(r => r.key === range)!.label.toLowerCase()}`} />}
      {!!ready?.unreadable && <p>{ready.unreadable} encrypted check-in(s) could not be read. They remain unchanged.</p>}
      <h3 className="font-bold mt-4">Activity calendar</h3>
      {data.status === 'error' ? <p>Activity history is unavailable.</p> : !ready ? <p>Loading recorded activities...</p> : <ActivityHeatmap days={activityDayCounts(ready.ledger.events)} now={now} />}
      <p className="text-sm mt-3">Daily reward limits use your device clock in Asia/Karachi. This is not an authoritative security clock or a measure of mental-health improvement.</p>
    </section>
    <RecordedBoard ownerUid={uid} legacyTotal={legacyTotal} pieces={ready ? ready.ledger.rewards.map(receipt => ({ ownerUid: uid, slot: receipt.slot_index - 1, completionId: receipt.completion_id, source: receipt.source_type, unlockedAt: ready.ledger.events.find(event => event.id === receipt.completion_id)?.completed_at ?? receipt.awarded_at, provenance: receipt.source_type === 'breathing' ? 'client-measured' : receipt.source_type === 'check_in' ? 'saved-consented-check-in' : 'explicit-persisted-exchange' })) : null} milestones={ready?.ledger.milestones.map(receipt => receipt.milestone) ?? []} />
  </>;
}
