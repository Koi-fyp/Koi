import { messagePollMs, unreadPollMs } from '@/lib/platform/messaging/poll-config';
import { createPoller } from '@/lib/platform/messaging/poller';

describe('messaging poll config', () => {
  it('uses documented defaults', () => { expect(messagePollMs(undefined)).toBe(8000); expect(unreadPollMs(undefined)).toBe(30000); });
  it('accepts valid integers', () => { expect(messagePollMs('5000')).toBe(5000); expect(unreadPollMs(' 45000 ')).toBe(45000); });
  it('falls back to the default for invalid input', () => { for (const bad of ['', 'abc', '1.5', '-5', '8e3', '12px']) { expect(messagePollMs(bad)).toBe(8000); expect(unreadPollMs(bad)).toBe(30000); } });
  it('clamps below the minimum', () => { expect(messagePollMs('100')).toBe(3000); expect(unreadPollMs('0')).toBe(10000); });
  it('clamps above the maximum', () => { expect(messagePollMs('999999')).toBe(60000); expect(unreadPollMs('9999999')).toBe(300000); });
});

describe('createPoller', () => {
  let visible = true, online = true;
  const env = { visible: () => visible, online: () => online };
  beforeEach(() => { jest.useFakeTimers(); visible = true; online = true; });
  afterEach(() => { jest.useRealTimers(); });
  const flush = (ms: number) => jest.advanceTimersByTimeAsync(ms);

  it('runs immediately and then every interval while visible', async () => {
    const run = jest.fn().mockResolvedValue(undefined), poller = createPoller({ run, intervalMs: 1000, env });
    poller.start(); await flush(0); expect(run).toHaveBeenCalledTimes(1);
    await flush(1000); expect(run).toHaveBeenCalledTimes(2); await flush(3000); expect(run).toHaveBeenCalledTimes(5); poller.stop();
  });
  it('does not poll while hidden and refreshes immediately when visible again', async () => {
    visible = false; const run = jest.fn().mockResolvedValue(undefined), poller = createPoller({ run, intervalMs: 1000, env });
    poller.start(); await flush(10000); expect(run).not.toHaveBeenCalled();
    visible = true; document.dispatchEvent(new Event('visibilitychange')); await flush(0); expect(run).toHaveBeenCalledTimes(1);
    visible = false; document.dispatchEvent(new Event('visibilitychange')); await flush(10000); expect(run).toHaveBeenCalledTimes(1);
    visible = true; window.dispatchEvent(new Event('focus')); await flush(0); expect(run).toHaveBeenCalledTimes(2); poller.stop();
  });
  it('never polls offline and resumes on the online event', async () => {
    online = false; const run = jest.fn().mockResolvedValue(undefined), poller = createPoller({ run, intervalMs: 1000, env });
    poller.start(); await flush(5000); expect(run).not.toHaveBeenCalled();
    online = true; window.dispatchEvent(new Event('online')); await flush(0); expect(run).toHaveBeenCalledTimes(1); poller.stop();
  });
  it('keeps one request in flight', async () => {
    let release: () => void = () => undefined; const run = jest.fn(() => new Promise<void>(r => { release = r; })), poller = createPoller({ run, intervalMs: 1000, env });
    poller.start(); await flush(0); poller.trigger(); window.dispatchEvent(new Event('focus')); await flush(5000); expect(run).toHaveBeenCalledTimes(1);
    release(); await flush(0); poller.stop();
  });
  it('backs off x2 after errors up to 60 s and resets after a success', async () => {
    const run = jest.fn().mockRejectedValue(new Error('down')), poller = createPoller({ run, intervalMs: 20000, env });
    poller.start(); await flush(0); expect(run).toHaveBeenCalledTimes(1);
    await flush(39999); expect(run).toHaveBeenCalledTimes(1); await flush(1); expect(run).toHaveBeenCalledTimes(2); // 40 s
    await flush(59999); expect(run).toHaveBeenCalledTimes(2); await flush(1); expect(run).toHaveBeenCalledTimes(3); // capped at 60 s
    await flush(60000); expect(run).toHaveBeenCalledTimes(4);
    run.mockResolvedValue(undefined); await flush(60000); expect(run).toHaveBeenCalledTimes(5); await flush(20000); expect(run).toHaveBeenCalledTimes(6); poller.stop();
  });
  it('stops for good on a 403 and reports it', async () => {
    const onFatal = jest.fn(), run = jest.fn().mockRejectedValue({ status: 403 }), poller = createPoller({ run, intervalMs: 1000, env, isFatal: e => (e as { status: number }).status === 403, onFatal });
    poller.start(); await flush(0); expect(onFatal).toHaveBeenCalledTimes(1);
    await flush(600000); window.dispatchEvent(new Event('focus')); document.dispatchEvent(new Event('visibilitychange')); await flush(10000); expect(run).toHaveBeenCalledTimes(1);
  });
});
