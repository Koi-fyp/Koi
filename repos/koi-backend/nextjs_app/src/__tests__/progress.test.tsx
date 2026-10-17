/** @jest-environment jsdom */
import React from 'react';
import { act, render, waitFor, cleanup, fireEvent } from '@testing-library/react';
const mockAuth = jest.fn();
jest.mock('dexie', () => jest.requireActual('../../node_modules/dexie/dist/dexie.js'));
jest.mock('@/contexts/AuthContext', () => ({ useAuth: () => mockAuth() }));
import { db, type JigsawProgressRecord, type MessageRecord } from '@/lib/db';
import { readProgress, summarizeCompletedExchanges } from '@/lib/progress/progressReadModel';
import { useProgress } from '@/hooks/useProgress';
import ProgressPage from '@/app/(authenticated)/progress/page';

const at = new Date('2026-10-17T10:00:00Z');
const message = (id: string, sender: 'user' | 'ai', additions: Partial<MessageRecord> = {}): MessageRecord => ({
  id, sender, ownerUid: 'a', conversationId: 'thread-a', content: 'v1:PBKDF2:fixture', timestamp: at,
  emotion: 'neutral', synced: false, ...additions,
});
const pair = [message('u', 'user'), message('r', 'ai', { replyTo: 'u' })];
const puzzle = (uid: string, total = 7): JigsawProgressRecord => ({
  uid, jigsaw_pieces: total, pieces_by_source: { conversations: total, check_ins: 0, breathing: 0, tasks: 0, bonuses: 0 },
  milestones_reached: [1, 1], last_updated: at,
});
beforeEach(async () => {
  mockAuth.mockReturnValue({ user: { uid: 'a' }, loading: false });
  await db.messages.clear(); await db.jigsawProgress.clear();
});
afterEach(cleanup);

it('counts successful owned exchanges once, including duplicate assistant rows and repeated reads', () => {
  const rows = [...pair, message('duplicate', 'ai', { replyTo: 'u', timestamp: new Date(+at + 5000) })];
  for (let i = 0; i < 3; i++) expect(summarizeCompletedExchanges('a', rows)).toEqual({
    completedExchanges: 1, conversationsWithReplies: 1, lastCompletedAt: at,
  });
});
it('excludes interrupted/failed user-only turns, foreign owners, legacy rows, mismatched threads and plaintext', () => {
  const rows = [message('pending', 'user'), message('legacy', 'user', { ownerUid: undefined }),
    message('legacy-reply', 'ai', { ownerUid: undefined, replyTo: 'legacy' }),
    message('foreign', 'user', { ownerUid: 'b' }), message('foreign-reply', 'ai', { replyTo: 'foreign' }),
    message('wrong-thread', 'ai', { replyTo: 'pending', conversationId: 'other' }),
    message('plain', 'user', { content: 'synthetic plaintext' }), message('plain-reply', 'ai', { replyTo: 'plain' }),
    message('no-source', 'ai')];
  expect(summarizeCompletedExchanges('a', rows)).toEqual({ completedExchanges: 0, conversationsWithReplies: 0, lastCompletedAt: null });
});
it('counts exchanges separately from conversations without interpreting emotional or crisis data', () => {
  expect(summarizeCompletedExchanges('a', [...pair, message('u2','user'), message('r2','ai',{replyTo:'u2',crisis_flag:true})]))
    .toMatchObject({ completedExchanges: 2, conversationsWithReplies: 1 });
});
it('reads only the selected owner and never grants/repeats rewards or modifies encrypted messages', async () => {
  await db.messages.bulkPut([...pair, message('b-user','user',{ownerUid:'b',conversationId:'thread-b'}), message('b-reply','ai',{ownerUid:'b',conversationId:'thread-b',replyTo:'b-user'})]);
  await db.jigsawProgress.bulkPut([puzzle('a'),puzzle('b',22)]);
  const beforeMessages = await db.messages.toArray();
  const beforePuzzle = await db.jigsawProgress.toArray();
  for (let i=0;i<3;i++) {
    expect(await readProgress('a')).toMatchObject({ completedExchanges:1, recordedProgress:{uid:'a',jigsaw_pieces:7} });
    expect(await readProgress('b')).toMatchObject({ completedExchanges:1, recordedProgress:{uid:'b',jigsaw_pieces:22} });
  }
  expect(await db.messages.toArray()).toEqual(beforeMessages);
  expect(await db.jigsawProgress.toArray()).toEqual(beforePuzzle);
});
it('preserves ownerless legacy ciphertext without adopting it', async () => {
  const orphan = message('legacy','ai',{ownerUid:undefined});
  await db.messages.put(orphan);
  expect(await readProgress('a')).toMatchObject({recordedProgress:null,completedExchanges:0});
  expect(await db.messages.get('legacy')).toEqual(orphan);
});
it('fails closed for an empty owner or invalid recorded counters without repairing them', async () => {
  await expect(readProgress('')).rejects.toThrow();
  await db.jigsawProgress.put(puzzle('a',-1));
  await expect(readProgress('a')).rejects.toThrow();
  expect((await db.jigsawProgress.get('a'))!.jigsaw_pieces).toBe(-1);
});

let latest: ReturnType<typeof useProgress>;
function Probe({uid}:{uid?:string}) { latest=useProgress(uid); return <span>{latest.state.status}</span>; }
it('updates live only after a persisted reply, without extra progress writes', async () => {
  const view=render(<Probe uid="a" />);
  await waitFor(()=>expect(latest.state.status).toBe('ready'));
  await act(async()=>{await db.messages.put(pair[0]);});
  await waitFor(()=>expect(latest.state).toMatchObject({status:'ready',summary:{completedExchanges:0}}));
  await act(async()=>{await db.messages.put(pair[1]);});
  await waitFor(()=>expect(latest.state).toMatchObject({status:'ready',summary:{completedExchanges:1}}));
  expect(await db.jigsawProgress.count()).toBe(0);
  view.unmount();
});
it('hides the old owner immediately on account switch/logout, and survives remount', async () => {
  await db.messages.bulkPut(pair); await db.jigsawProgress.put(puzzle('a'));
  const view=render(<Probe uid="a" />);
  await waitFor(()=>expect(latest.state).toMatchObject({status:'ready',summary:{completedExchanges:1}}));
  view.rerender(<Probe uid="b" />);
  expect(latest.state).not.toHaveProperty('summary.recordedProgress.uid','a');
  await waitFor(()=>expect(latest.state).toMatchObject({status:'ready',uid:'b',summary:{completedExchanges:0,recordedProgress:null}}));
  view.rerender(<Probe />); expect(latest.state.status).toBe('signed-out'); view.unmount();
  render(<Probe uid="a" />);
  await waitFor(()=>expect(latest.state).toMatchObject({status:'ready',summary:{recordedProgress:{jigsaw_pieces:7},completedExchanges:1}}));
});
it('renders saved totals and labels retained illustrations/charts as previews', async () => {
  await db.messages.bulkPut(pair); await db.jigsawProgress.put(puzzle('a'));
  const view=render(<ProgressPage />);
  expect(view.getByRole('status')).toHaveTextContent('Loading');
  await waitFor(()=>expect(view.getByRole('heading',{name:'Your Progress'})).toBeInTheDocument());
  expect(view.getByText('Completed Exchanges')).toBeInTheDocument();
  expect(view.getByText('Recorded Milestones')).toBeInTheDocument();
  expect(view.getByRole('note')).toHaveTextContent('previews');
  expect(view.getByRole('heading',{name:'Mood Trends (Preview)'})).toBeInTheDocument();
  expect(view.getByText('New puzzle rewards are not available yet.',{exact:false})).toBeInTheDocument();
  expect(view.queryByText('247')).not.toBeInTheDocument();
  expect(view.queryByText('Days Streak')).not.toBeInTheDocument();
  expect(view.queryByText('Avg Mood')).not.toBeInTheDocument();
});
it('shows a recoverable read error instead of inventing a zero reward balance', async () => {
  const failure=jest.spyOn(db,'transaction').mockRejectedValueOnce(new Error('unavailable') as never);
  const view=render(<ProgressPage />);
  await waitFor(()=>expect(view.getByRole('alert')).toBeInTheDocument());
  expect(view.queryByText('Recorded Puzzle Pieces')).not.toBeInTheDocument();
  failure.mockRestore(); fireEvent.click(view.getByRole('button',{name:'Try again'}));
  await waitFor(()=>expect(view.getByText('Recorded Puzzle Pieces')).toBeInTheDocument());
});
