import { MAX_BACKOFF_MS } from './poll-config';

export interface PollerEnv { visible(): boolean; online(): boolean }
export interface PollerOptions {
  run: () => Promise<void>;
  intervalMs: number;
  /** An error for which polling must stop for good (access lost). */
  isFatal?: (error: unknown) => boolean;
  onFatal?: (error: unknown) => void;
  onError?: (error: unknown) => void;
  env?: PollerEnv;
}
const browserEnv: PollerEnv = { visible: () => !document.hidden, online: () => navigator.onLine !== false };
/**
 * Visibility-aware poller: one request in flight, no polling while hidden or offline, immediate refresh on
 * visibilitychange / focus / online, delay doubles after each error (capped), stops on a fatal error.
 */
export function createPoller(options: PollerOptions) {
  const env = options.env ?? browserEnv;
  let timer: ReturnType<typeof setTimeout> | null = null, started = false, inFlight = false, delay = options.intervalMs;
  const clear = () => { if (timer) { clearTimeout(timer); timer = null; } };
  const schedule = () => { clear(); if (started && env.visible() && env.online()) timer = setTimeout(tick, delay); };
  async function tick() {
    timer = null;
    if (!started || inFlight || !env.visible() || !env.online()) return;
    inFlight = true;
    try { await options.run(); delay = options.intervalMs; }
    catch (error) {
      if (options.isFatal?.(error)) { started = false; detach(); inFlight = false; options.onFatal?.(error); return; }
      delay = Math.min(delay * 2, Math.max(MAX_BACKOFF_MS, options.intervalMs)); options.onError?.(error);
    }
    inFlight = false; schedule();
  }
  const wake = () => { if (!started) return; clear(); void tick(); };
  const onVisibility = () => { if (env.visible()) wake(); else clear(); };
  const onOffline = () => clear();
  function detach() { clear(); if (typeof document === 'undefined') return; document.removeEventListener('visibilitychange', onVisibility); window.removeEventListener('focus', wake); window.removeEventListener('online', wake); window.removeEventListener('offline', onOffline); }
  return {
    start() {
      if (started) return; started = true; delay = options.intervalMs;
      if (typeof document !== 'undefined') { document.addEventListener('visibilitychange', onVisibility); window.addEventListener('focus', wake); window.addEventListener('online', wake); window.addEventListener('offline', onOffline); }
      void tick();
    },
    /** Refresh now (no-op while hidden, offline or already in flight). */
    trigger: wake,
    stop() { started = false; detach(); },
  };
}
