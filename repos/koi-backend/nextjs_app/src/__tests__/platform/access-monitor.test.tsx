import React from 'react';
import { act, render, screen, waitFor } from '@testing-library/react';
import { ReadableStream } from 'node:stream/web';
import { TextDecoder, TextEncoder } from 'node:util';
import { useAccessMonitor } from '@/lib/platform/access-monitor';
Object.defineProperty(globalThis, 'TextDecoder', { value: TextDecoder, configurable: true });
Object.defineProperty(globalThis, 'TextEncoder', { value: TextEncoder, configurable: true });
function View({ user }: { user: any }) { const state = useAccessMonitor('patient_a', () => user); return <div>{state.ready ? <span key={state.generation}>PROTECTED ANSWERS generation {state.generation}</span> : <span>Locked</span>}</div>; }
let controller: any, user: any, previousFetch: typeof fetch;
beforeEach(() => {
  previousFetch = global.fetch; user = { uid: 'patient_a', getIdToken: async () => 'test-id-token' };
  global.fetch = jest.fn(async (_url, options) => {
    const stream = new ReadableStream({ start(c) { controller = c; options.signal.addEventListener('abort', () => { try { c.close(); } catch {} }); } });
    return { ok: true, body: stream } as any;
  });
});
afterEach(() => { global.fetch = previousFetch; jest.useRealTimers(); });
const emit = () => controller.enqueue(new TextEncoder().encode('event: authorization_changed\ndata: {"event":"authorization_changed","authorization_revision":1,"occurred_at":"2026-10-19T00:00:00Z"}\n\n'));
it('locks before authorization, remounts after a changed hint, and clears on stream disconnect', async () => {
  render(<View user={user} />); expect(screen.getByText('Locked')).toBeVisible(); await waitFor(() => expect(controller).toBeDefined());
  await act(async () => { emit(); }); expect(screen.getByText(/PROTECTED ANSWERS generation 1/)).toBeVisible();
  await act(async () => { emit(); }); expect(screen.getByText(/PROTECTED ANSWERS generation 2/)).toBeVisible();
  await act(async () => { controller.close(); }); expect(screen.getByText('Locked')).toBeVisible(); expect(document.body.textContent).not.toContain('PROTECTED');
  expect(global.fetch).toHaveBeenCalledWith('/api/v1/me/access-events', expect.objectContaining({ cache: 'no-store', credentials: 'omit' }));
});
it('clears protected content on offline and UID changes', async () => {
  const view = render(<View user={user} />); await waitFor(() => expect(controller).toBeDefined()); await act(async () => { emit(); });
  user.uid = 'patient_b'; view.rerender(<View user={user} />); await act(async () => { emit(); }); await waitFor(() => expect(screen.getByText('Locked')).toBeVisible());
});
it('locks a stalled stream when its heartbeat deadline expires', async () => {
  jest.useFakeTimers(); render(<View user={user} />);
  await act(async () => { await Promise.resolve(); await Promise.resolve(); });
  await act(async () => { emit(); }); expect(document.body.textContent).toContain('PROTECTED');
  await act(async () => { jest.advanceTimersByTime(8001); }); expect(screen.getByText('Locked')).toBeVisible();
});
