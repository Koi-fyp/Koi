import React from 'react';
import { act, fireEvent, render, screen } from '@testing-library/react';
import { webcrypto } from 'crypto';
import { TextEncoder } from 'util';
jest.mock('@/components/companion/CompanionScene.module.css', () => ({}));
jest.mock('@/components/progress/BreathingActivityBridge', () => ({ useBreathingResultCallback: () => undefined }));
let mockUid = 'synthetic-breathing-owner';
const mockRecord = jest.fn();
jest.mock('@/lib/firebase', () => ({ auth: { get currentUser() { return { uid: mockUid }; } } }));
jest.mock('@/lib/activities/activityLedger', () => ({ activityLedger: { record: (...args: unknown[]) => mockRecord(...args) } }));
import ExerciseDirector from '@/components/companion/ExerciseDirector';
import { breathingEligible, saveBreathingResult, type BreathingResult } from '@/lib/activities/breathingActivity';
import type { ChatServerEvent } from '@/lib/conversation/chatContract';
const start = { id: 1, event: { event: 'ui_action', data: { name: 'start_breathing', args: { inhale_s: 4, exhale_s: 6, cycles: 6, cue_audio: ['Breathe in', 'Breathe out'] } } } as ChatServerEvent };
const result = (): BreathingResult => ({ sessionId: 'c5ead599-795f-4163-ad6c-7e32c028f199', startedAt: '2026-10-18T10:00:00.000Z', endedAt: '2026-10-18T10:01:00.000Z', cyclesPlanned: 6, cyclesCompleted: 6, durationMs: 60000, endReason: 'completed' });
beforeEach(() => { jest.useFakeTimers(); mockUid = 'synthetic-breathing-owner'; mockRecord.mockReset().mockResolvedValue({ outcome: 'awarded' }); });
afterEach(() => jest.useRealTimers());
it.each([[4, 60000, 'completed', false], [5, 47999, 'completed', false], [5, 48000, 'completed', true], [6, 60000, 'completed', true], [6, 60000, 'handoff', false], [6, 60000, 'user_stop', false], [6, 60000, 'navigation', false]])('validates cycles/duration/reason: %s %s %s', (cycles, duration, reason, eligible) => {
  expect(breathingEligible({ ...result(), cyclesCompleted: cycles as number, durationMs: duration as number, endReason: reason as BreathingResult['endReason'] })).toBe(eligible);
});
it('reports a real monotonic 60-second run exactly once with a UUID, not signed token identity', () => {
  const onResult = jest.fn(), queue = jest.fn();
  render(<ExerciseDirector events={[start]} onRequest={jest.fn()} onQueueClientEvent={queue} onBreathingResult={onResult} />);
  act(() => jest.advanceTimersByTime(60000));
  expect(onResult).toHaveBeenCalledTimes(1); expect(onResult.mock.calls[0][0]).toMatchObject({ cyclesPlanned: 6, cyclesCompleted: 6, durationMs: 60000, endReason: 'completed' });
  expect(onResult.mock.calls[0][0].sessionId).toMatch(/^[0-9a-f-]{36}$/); expect(queue).toHaveBeenCalledWith('playback_done');
  act(() => jest.advanceTimersByTime(60000)); expect(onResult).toHaveBeenCalledTimes(1);
});
it('excludes pauses from completed cycles and active monotonic duration even if wall clock jumps', () => {
  const onResult = jest.fn(); render(<ExerciseDirector events={[start]} onRequest={jest.fn()} onQueueClientEvent={jest.fn()} onBreathingResult={onResult} />);
  act(() => jest.advanceTimersByTime(20000)); fireEvent.click(screen.getByRole('button', { name: 'Pause' }));
  act(() => { jest.setSystemTime(new Date('2030-01-01T00:00:00Z')); jest.advanceTimersByTime(90000); }); expect(onResult).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole('button', { name: 'Resume' })); act(() => jest.advanceTimersByTime(40000));
  expect(onResult.mock.calls[0][0]).toMatchObject({ durationMs: 60000, cyclesCompleted: 6, endReason: 'completed' });
});
it('handoff interrupts, never resumes from later state/done, and cannot qualify', () => {
  const onResult = jest.fn(), queue = jest.fn();
  const view = render(<ExerciseDirector events={[start]} onRequest={jest.fn()} onQueueClientEvent={queue} onBreathingResult={onResult} />);
  act(() => jest.advanceTimersByTime(30000));
  const handoff = { id: 2, event: { event: 'handoff', data: { to: 'crisis', reason: 'synthetic safety fixture' } } as ChatServerEvent };
  view.rerender(<ExerciseDirector events={[start, handoff]} onRequest={jest.fn()} onQueueClientEvent={queue} onBreathingResult={onResult} />);
  expect(screen.queryByRole('region', { name: 'Paced breathing activity' })).toBeNull();
  expect(onResult.mock.calls[0][0]).toMatchObject({ endReason: 'handoff', cyclesCompleted: 3 });
  expect(breathingEligible(onResult.mock.calls[0][0])).toBe(false);
  view.rerender(<ExerciseDirector events={[start, handoff, { id: 3, event: { event: 'state', data: { exercise_state: 'synthetic-rotating-token' } } as ChatServerEvent }]} onRequest={jest.fn()} onQueueClientEvent={queue} onBreathingResult={onResult} />);
  act(() => jest.advanceTimersByTime(90000)); expect(onResult).toHaveBeenCalledTimes(1); expect(queue).not.toHaveBeenCalledWith('playback_done');
});
it('user stop reports interrupted measurement and navigation reports once', async () => {
  const onResult = jest.fn(); const view = render(<ExerciseDirector events={[start]} onRequest={jest.fn()} onQueueClientEvent={jest.fn()} onBreathingResult={onResult} />);
  act(() => jest.advanceTimersByTime(50000)); fireEvent.click(screen.getByRole('button', { name: 'Stop' }));
  expect(onResult.mock.calls[0][0]).toMatchObject({ endReason: 'user_stop', cyclesCompleted: 5 }); expect(breathingEligible(onResult.mock.calls[0][0])).toBe(false);
  view.unmount();
  const second = render(<ExerciseDirector events={[start]} onRequest={jest.fn()} onQueueClientEvent={jest.fn()} onBreathingResult={onResult} />);
  act(() => jest.advanceTimersByTime(50000)); second.unmount(); await act(async () => { jest.runAllTicks(); });
  expect(onResult.mock.calls[1][0]).toMatchObject({ endReason: 'navigation', cyclesCompleted: 5 });
});
it('hashes stable owner/session identity, rejects stale/invalid timing and never hashes exercise_state', async () => {
  Object.defineProperty(globalThis.crypto, 'subtle', { configurable: true, value: webcrypto.subtle }); Object.assign(globalThis, { TextEncoder });
  await saveBreathingResult(mockUid, result()); await saveBreathingResult(mockUid, result());
  expect(mockRecord.mock.calls[0][0].completionId).toBe(mockRecord.mock.calls[1][0].completionId);
  expect(mockRecord.mock.calls[0][0]).toMatchObject({ source: 'breathing', sourceId: result().sessionId, evidence: { durationMs: 60000, measurement: 'client-measured' } });
  expect(await saveBreathingResult(mockUid, { ...result(), durationMs: 1 })).toEqual({ outcome: 'ineligible' }); expect(mockRecord).toHaveBeenCalledTimes(2);
});

it('an observer failure never suppresses the existing playback_done completion behavior',()=>{
 const queue=jest.fn();render(<ExerciseDirector events={[start]} onRequest={jest.fn()} onQueueClientEvent={queue} onBreathingResult={()=>{throw new Error('synthetic observer failure');}}/>);
 act(()=>jest.advanceTimersByTime(60000));expect(queue).toHaveBeenCalledWith('playback_done');expect(screen.getByText('Activity complete')).toBeInTheDocument();
});
