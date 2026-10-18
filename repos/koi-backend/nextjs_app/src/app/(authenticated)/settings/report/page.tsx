'use client';
import { useEffect, useMemo, useState } from 'react';
import { liveQuery } from 'dexie';
import BackButton from '../components/BackButton';
import { useAuth } from '@/contexts/AuthContext';
import { useActivityData } from '@/hooks/useActivityData';
import { db } from '@/lib/db';
import { karachiDay } from '@/lib/activities/rewardPreview';
import { withOwnedDecryptor } from '@/lib/history/ownedDecryptor';
import { buildWellnessReport, REPORT_DISCLAIMER, type ConversationActivity } from '@/lib/report/wellnessReport';
import CheckInChart from '@/components/progress/CheckInChart';

type Owned = ConversationActivity & { firstUserCiphertext: string | null };
/** Owned message-row metadata only (ids, days); content stays ciphertext unless titles are explicitly requested. */
function useConversationActivity(uid: string | undefined) {
  const [state, setState] = useState<{ owner: string; conversations: Owned[] } | null>(null);
  useEffect(() => {
    if (!uid) return;
    const subscription = liveQuery(async () => {
      const rows = await db.messages.filter(row => row.ownerUid === uid).toArray();
      const groups = new Map<string, Owned & { days: Set<string>; firstAt: number }>();
      for (const row of rows) {
        if (!row.conversationId || !(row.timestamp instanceof Date) || !Number.isFinite(+row.timestamp)) continue;
        const group = groups.get(row.conversationId) ?? { conversationId: row.conversationId, days: new Set<string>(), dayKeys: new Set<string>(), firstUserCiphertext: null, firstAt: Infinity };
        group.days.add(karachiDay(row.timestamp.toISOString()));
        if (row.sender === 'user' && +row.timestamp < group.firstAt) { group.firstAt = +row.timestamp; group.firstUserCiphertext = row.content; }
        groups.set(row.conversationId, group);
      }
      return [...groups.values()].map(({ conversationId, days, firstUserCiphertext }) => ({ conversationId, dayKeys: days, firstUserCiphertext }));
    }).subscribe({ next: conversations => setState({ owner: uid, conversations }), error: () => setState({ owner: uid, conversations: [] }) });
    return () => subscription.unsubscribe();
  }, [uid]);
  return state?.owner === uid ? state.conversations : null;
}

export default function WellnessReportPage() {
  const { user } = useAuth();
  const uid = user?.uid;
  const data = useActivityData(uid);
  const conversations = useConversationActivity(uid);
  const today = karachiDay(new Date(Date.now()).toISOString());
  const [from, setFrom] = useState(() => karachiDay(new Date(Date.now() - 29 * 86_400_000).toISOString()));
  const [to, setTo] = useState(today);
  const [includeTitles, setIncludeTitles] = useState(false);
  const [titles, setTitles] = useState<{ key: string; status: 'ready' | 'locked'; values: Record<string, string> } | null>(null);
  const ready = data.status === 'ready' ? data : null;
  const report = useMemo(() => {
    if (!ready || !conversations || !from || !to || from > to) return null;
    return buildWellnessReport({ from, to, entries: ready.locked ? [] : ready.entries, events: ready.ledger.events, rewards: ready.ledger.rewards,
      milestones: ready.ledger.milestones, conversations });
  }, [ready, conversations, from, to]);
  const titleKey = `${uid}:${report?.conversations.join(',')}`;
  useEffect(() => {
    if (!includeTitles || !uid || !report || !conversations) return;
    const controller = new AbortController();
    const wanted = conversations.filter(c => report.conversations.includes(c.conversationId) && c.firstUserCiphertext);
    void withOwnedDecryptor(uid, controller.signal, async decryptOwned => {
      const values: Record<string, string> = {};
      for (const c of wanted) values[c.conversationId] = (await decryptOwned(c.firstUserCiphertext!)).trim().slice(0, 80);
      return values;
    }).then(result => { if (!controller.signal.aborted) setTitles({ key: titleKey, status: result.status === 'ready' ? 'ready' : 'locked', values: result.status === 'ready' ? result.value : {} }); });
    return () => controller.abort();
  }, [includeTitles, titleKey]);
  const shownTitles = includeTitles && titles?.key === titleKey ? titles : null;
  const range = report ? `${report.from} to ${report.to}` : '';
  return <div className="report-page" style={{ padding: '1.5rem', maxWidth: '640px', margin: '0 auto', minHeight: '100vh' }}>
    <div className="no-print"><BackButton /></div>
    <h1 style={{ fontWeight: 900, fontSize: '2rem', letterSpacing: '-0.03em', marginBottom: '0.5rem' }}>Wellness Report</h1>
    <form className="no-print neo-card p-4 my-4" onSubmit={event => event.preventDefault()} aria-label="Report options">
      <div className="flex flex-wrap gap-4">
        <label className="block text-sm">From (Asia/Karachi)<input className="neo-input block mt-1" type="date" value={from} max={to || today} onChange={event => setFrom(event.target.value)} /></label>
        <label className="block text-sm">To<input className="neo-input block mt-1" type="date" value={to} min={from} max={today} onChange={event => setTo(event.target.value)} /></label>
      </div>
      <label className="block text-sm mt-3"><input type="checkbox" checked={includeTitles} onChange={event => setIncludeTitles(event.target.checked)} /> Include my message titles (the first message of each conversation). Anyone who sees the printout can read them.</label>
      <button type="button" className="neo-btn-primary mt-4" disabled={!report} onClick={() => window.print()}>Print / Save as PDF</button>
    </form>
    {/* The report itself is a white "paper" document under the controls card; it prints as a plain page. */}
    <div className="koi-paper" data-testid="report-paper">
    <p role="note" className="font-bold border-2 border-black rounded-lg p-3 mb-4">{REPORT_DISCLAIMER}</p>
    {!uid ? <p role="status">Sign in to build a report.</p>
      : data.status === 'error' ? <p role="alert">Saved activity could not be read. No report was built.</p>
      : !report ? <p role="status">{from > to ? 'Choose a start date on or before the end date.' : 'Loading saved data…'}</p>
      : <article aria-label={`Report for ${range}`}>
        <p className="text-sm">Period: {range} · Built on this device from data saved in KOI.</p>
        <section className="my-5"><h2 className="font-bold text-xl">Check-ins</h2>
          {ready?.locked ? <p>Saved check-in ratings are locked on this device and are not included.</p>
            : !report.ratings ? <p>No data yet.</p> : <>
              <p>{report.checkIns.length} saved check-in{report.checkIns.length === 1 ? '' : 's'} (self-reported, 1 to 5).</p>
              <table className="w-full text-sm my-2" aria-label="Check-in summary"><thead className="text-left"><tr><th>Rating</th><th>Lowest</th><th>Average</th><th>Highest</th></tr></thead><tbody>
                {(['mood', 'connection', 'energy'] as const).map(key => <tr key={key}><td>{key[0].toUpperCase() + key.slice(1)}</td><td>{report.ratings![key].min}</td><td>{report.ratings![key].average}</td><td>{report.ratings![key].max}</td></tr>)}
              </tbody></table>
              <CheckInChart entries={report.checkIns} from={Date.parse(`${report.from}T00:00:00+05:00`)} to={Date.parse(`${report.to}T23:59:59+05:00`)} title="Check-in ratings in this period" />
            </>}
        </section>
        <section className="my-5"><h2 className="font-bold text-xl">Activities and pieces</h2>
          <dl className="grid grid-cols-2 gap-2 text-sm">
            <div><dt className="font-bold">Check-ins saved</dt><dd>{report.activity.checkIns}</dd></div>
            <div><dt className="font-bold">Breathing sessions</dt><dd>{report.activity.breathingSessions}</dd></div>
            <div><dt className="font-bold">Completed conversations</dt><dd>{report.activity.completedConversations}</dd></div>
            <div><dt className="font-bold">Pieces earned in this period</dt><dd>{report.piecesEarned}</dd></div>
            <div><dt className="font-bold">Conversations with messages</dt><dd>{report.conversations.length}</dd></div>
            <div><dt className="font-bold">Milestones reached (all time)</dt><dd>{report.milestones.length ? report.milestones.map(m => `${m} pieces`).join(', ') : 'None yet'}</dd></div>
          </dl>
          {includeTitles && <div className="mt-4"><h3 className="font-bold">Message titles</h3>
            {!report.conversations.length ? <p>No data yet.</p> : !shownTitles ? <p role="status">Unlocking titles…</p>
              : shownTitles.status === 'locked' ? <p>Titles are locked on this device and are not included.</p>
              : <ul className="list-disc pl-5">{report.conversations.map(id => <li key={id} dir="auto">{shownTitles.values[id] || 'Untitled conversation'}</li>)}</ul>}
          </div>}
        </section>
        <p className="text-sm mt-6">This report contains no conversation content{includeTitles ? ' other than the titles you chose to include' : ''}, crisis information or risk scores. {REPORT_DISCLAIMER}</p>
      </article>}
    </div>
  </div>;
}
