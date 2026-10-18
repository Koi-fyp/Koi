'use client';
import { useEffect, useRef, useState, type FormEvent } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { auth } from '@/lib/firebase';
import { useActivityData } from '@/hooks/useActivityData';
import { checkInAvailable, saveCheckIn } from '@/lib/checkins/checkInService';
import RecordedBoard from './RecordedBoard';

export default function ActivityAvailability({ legacyTotal }: { legacyTotal?: number }) {
  const { user } = useAuth();
  return user ? <OwnedActivities key={user.uid} uid={user.uid} legacyTotal={legacyTotal} /> : null;
}
function OwnedActivities({ uid, legacyTotal }: { uid: string; legacyTotal?: number }) {
  const data = useActivityData(uid);
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
      <dl className="text-sm space-y-2 my-4">
        <div><dt className="font-bold">Completed conversations</dt><dd>{ready ? new Set(ready.ledger.events.filter(event => event.source_type === 'conversation').map(event => event.source_id)).size : data.status === 'error' ? 'Unavailable' : 'Loading recorded completions…'}</dd></div>
        <div><dt className="font-bold">Earned pieces</dt><dd>{ready ? `${ready.ledger.rewards.length} of 25` : data.status === 'error' ? 'Unavailable' : 'Loading earned pieces…'}</dd></div>
      </dl>
      {data.status === 'error' && <p role="alert">Saved activities could not be loaded. Your records have not been changed.</p>}
      <h3 className="font-bold">Mood and activity history</h3>
      {data.status === 'error' ? <p>Saved rating history is unavailable.</p> : !ready ? <p>Loading saved ratings...</p> : ready.locked ? <p>Saved ratings are locked. Unlock the existing key to view them.</p> : !ready?.entries.length ? <p>No recorded check-ins yet.</p> : <>
        <div className="overflow-x-auto"><svg role="img" aria-label="Recorded mood, connection and energy ratings, scale 1 to 5" viewBox="0 0 320 140" className="w-full max-w-md">
          {(['mood', 'connection', 'energy'] as const).map((name, index) => <g key={name}><polyline key={name} fill="none" stroke={['#845EC2', '#2D63EB', '#18783B'][index]} strokeWidth="2" points={ready.entries.slice(-30).map((entry, i, all) => `${20 + i * 280 / Math.max(1, all.length - 1)},${120 - (entry[name] - 1) * 25}`).join(' ')} />{ready.entries.slice(-30).map((entry, i, all) => <circle key={entry.id} cx={20 + i * 280 / Math.max(1, all.length - 1)} cy={120 - (entry[name] - 1) * 25} r={3} fill={['#845EC2', '#2D63EB', '#18783B'][index]} />)}</g>)}
        </svg></div>
        <p className="text-sm">Mood (purple), Connection (blue), Energy (green). Latest 30 saved entries; the table provides exact values.</p>
        <div className="overflow-x-auto"><table className="w-full text-sm" aria-label="Saved check-in ratings"><thead><tr><th>Saved time</th><th>Mood</th><th>Connection</th><th>Energy</th></tr></thead><tbody>{ready.entries.slice(-30).map(entry => <tr key={entry.id}><td>{new Date(entry.completedAt).toLocaleString('en-PK', { timeZone: 'Asia/Karachi' })}</td><td>{entry.mood}</td><td>{entry.connection}</td><td>{entry.energy}</td></tr>)}</tbody></table></div>
      </>}
      {!!ready?.unreadable && <p>{ready.unreadable} encrypted check-in(s) could not be read. They remain unchanged.</p>}
      <h3 className="font-bold mt-4">Recorded activity days (Asia/Karachi)</h3>
      {ready && ready.ledger.events.length ? <ul className="flex flex-wrap gap-2">{Object.entries(ready.ledger.events.reduce<Record<string, number>>((days, event) => { days[event.day_key] = (days[event.day_key] ?? 0) + 1; return days; }, {})).sort(([a], [b]) => a.localeCompare(b)).slice(-60).map(([day, count]) => <li className="border-2 border-black rounded-lg p-2" key={day}>{day}: {count} saved activities</li>)}</ul> : <p>{data.status === 'error' ? 'Activity history is unavailable.' : !ready ? 'Loading recorded activities...' : 'No recorded activities yet.'}</p>}
      <p className="text-sm mt-3">Daily reward limits use your device clock in Asia/Karachi. This is not an authoritative security clock or a measure of mental-health improvement.</p>
    </section>
    <RecordedBoard ownerUid={uid} legacyTotal={legacyTotal} pieces={ready ? ready.ledger.rewards.map(receipt => ({ ownerUid: uid, slot: receipt.slot_index - 1, completionId: receipt.completion_id, source: receipt.source_type, unlockedAt: ready.ledger.events.find(event => event.id === receipt.completion_id)?.completed_at ?? receipt.awarded_at, provenance: receipt.source_type === 'breathing' ? 'client-measured' : receipt.source_type === 'check_in' ? 'saved-consented-check-in' : 'explicit-persisted-exchange' })) : null} milestones={ready?.ledger.milestones.map(receipt => receipt.milestone) ?? []} />
  </>;
}
