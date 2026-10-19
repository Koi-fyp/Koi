import React, { StrictMode, useEffect } from 'react';
import { act, fireEvent, render, screen } from '@testing-library/react';
import { EnvironmentProvider, EnvironmentSession, useEnvironment, useEnvironmentObservers } from '@/contexts/EnvironmentContext';
import { ConversationSession } from '@/lib/conversation/ConversationSession';
import type { ChatServerEvent } from '@/lib/conversation/chatContract';
import ExerciseDirector from '@/components/companion/ExerciseDirector';
jest.mock('@/components/companion/CompanionScene.module.css', () => ({}));
jest.mock('@/components/progress/BreathingActivityBridge', () => ({ useBreathingResultCallback: () => undefined }));

const start: ChatServerEvent = { event: 'ui_action', data: { name: 'start_breathing', args: { inhale_s: 4, exhale_s: 6, cycles: 6, cue_audio: ['In', 'Out'] } } };
function Probe({ events = [], interruptKey = 0 }: { events?: Array<{ id: number; event: ChatServerEvent }>; interruptKey?: number }) {
  const environment = useEnvironment('call'), observers = useEnvironmentObservers();
  return <><output aria-label="Environment mood">{environment.mood}</output><ExerciseDirector events={events} interruptKey={interruptKey}
    onActivityChange={observers?.breathing} onRequest={() => {}} onQueueClientEvent={() => {}} /></>;
}
function fixture() {
  let emit!: (event: ChatServerEvent) => void;
  const session = new ConversationSession({ send: (_request, options) => new Promise(() => { emit = event => options?.onEvent?.(event); }) });
  return { session, emotion: () => emit({ event: 'companion_state', data: { emotion: 'joy', intensity: 1 } }) };
}
beforeEach(() => jest.useFakeTimers());
afterEach(() => jest.useRealTimers());
it('uses actual breathing state: completion restores emotion while completed card remains mounted', () => {
  const f = fixture();
  const view = render(<EnvironmentProvider><EnvironmentSession session={f.session}><Probe /></EnvironmentSession></EnvironmentProvider>);
  act(() => { void f.session.send('Hello'); f.emotion(); }); expect(screen.getByRole('status', { name: 'Environment mood' })).toHaveTextContent('joy');
  view.rerender(<EnvironmentProvider><EnvironmentSession session={f.session}><Probe events={[{ id: 1, event: start }]} /></EnvironmentSession></EnvironmentProvider>);
  expect(screen.getByRole('status', { name: 'Environment mood' })).toHaveTextContent('calm');
  act(() => jest.advanceTimersByTime(60000));
  expect(screen.getByRole('status', { name: 'Environment mood' })).toHaveTextContent('joy'); expect(screen.getByText('Activity complete')).toBeInTheDocument();
});
it.each(['stop', 'interrupt', 'invalid', 'server-stop', 'navigate'])('observes %s without replaying exercise actions', async kind => {
  const f = fixture();
  const wrap = (events: Array<{ id: number; event: ChatServerEvent }>, interruptKey = 0, show = true) => <EnvironmentProvider><EnvironmentSession session={f.session}>
    {show ? <Probe events={events} interruptKey={interruptKey} /> : <Display />}
  </EnvironmentSession></EnvironmentProvider>;
  const events = [{ id: 1, event: start }]; const view = render(wrap(events));
  act(() => { void f.session.send('Hello'); f.emotion(); }); expect(screen.getByRole('status', { name: 'Environment mood' })).toHaveTextContent('calm');
  fireEvent.click(screen.getByRole('button', { name: 'Pause' })); expect(screen.getByRole('status', { name: 'Environment mood' })).toHaveTextContent('calm');
  if (kind === 'stop') fireEvent.click(screen.getByRole('button', { name: 'Stop' }));
  if (kind === 'interrupt') view.rerender(wrap(events, 2));
  if (kind === 'invalid') view.rerender(wrap([...events, { id: 2, event: { event: 'ui_action', data: { name: 'start_breathing', args: {} } } }]));
  if (kind === 'server-stop') view.rerender(wrap([...events, { id: 2, event: { event: 'ui_action', data: { name: 'stop_breathing', args: {} } } }]));
  if (kind === 'navigate') { view.rerender(wrap(events, 0, false)); await act(async () => { jest.runAllTicks(); }); }
  expect(screen.getByRole('status', { name: 'Environment mood' })).toHaveTextContent('joy');
});
function Display() { const environment = useEnvironment('chat'); return <output aria-label="Environment mood">{environment.mood}</output>; }
it('environment updates do not write browser storage or open IndexedDB', () => {
  const storage = jest.spyOn(Storage.prototype, 'setItem');
  const database = jest.spyOn(indexedDB, 'open');
  try {
    const f = fixture();
    const view = render(<EnvironmentProvider><EnvironmentSession session={f.session}><Probe /></EnvironmentSession></EnvironmentProvider>);
    act(() => { void f.session.send('Hello'); f.emotion(); });
    view.rerender(<EnvironmentProvider><EnvironmentSession session={f.session}><Probe events={[{ id: 1, event: start }]} /></EnvironmentSession></EnvironmentProvider>);
    act(() => jest.advanceTimersByTime(60000));
    expect(storage).not.toHaveBeenCalled(); expect(database).not.toHaveBeenCalled();
  } finally { storage.mockRestore(); database.mockRestore(); }
});
it('shares mood across route/navigation consumers without remounting navigation, and resets on session/account changes', () => {
  const f = fixture(), mounted = jest.fn(), unmounted = jest.fn();
  function Navigation() { useEffect(() => { mounted(); return unmounted; }, []); return <Display />; }
  const wrap = (session: ConversationSession, account = 'one', route = 'chat') => <StrictMode><EnvironmentProvider key={account}>
    <Navigation /><EnvironmentSession key={session.conversationId} session={session}><Display key={route} /></EnvironmentSession>
  </EnvironmentProvider></StrictMode>;
  const view = render(wrap(f.session));
  const mounts = mounted.mock.calls.length, unmounts = unmounted.mock.calls.length;
  act(() => { void f.session.send('Hello'); f.emotion(); });
  expect(screen.getAllByRole('status', { name: 'Environment mood' }).every(node => node.textContent === 'joy')).toBe(true);
  view.rerender(wrap(f.session, 'one', 'call'));
  expect(screen.getAllByRole('status', { name: 'Environment mood' }).every(node => node.textContent === 'joy')).toBe(true);
  view.rerender(wrap(new ConversationSession({ send: jest.fn() })));
  expect(screen.getAllByRole('status', { name: 'Environment mood' }).every(node => node.textContent === 'neutral')).toBe(true);
  expect(mounted).toHaveBeenCalledTimes(mounts); expect(unmounted).toHaveBeenCalledTimes(unmounts);
  view.rerender(wrap(f.session, 'two'));
  expect(screen.getAllByRole('status', { name: 'Environment mood' }).every(node => node.textContent === 'neutral')).toBe(true);
});
