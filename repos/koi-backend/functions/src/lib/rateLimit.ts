import type { RateLimitState, RateLimitResult } from '../types/index';

const WINDOW_MS = 60_000;
const HARD_LIMIT = 15;
const SOFT_LIMIT = 12;

const store = new Map<string, RateLimitState>();

function getState(userId: string): RateLimitState {
  const now = Date.now();
  const existing = store.get(userId);

  if (!existing || now - existing.windowStart >= WINDOW_MS) {
    const fresh: RateLimitState = { count: 0, windowStart: now };
    store.set(userId, fresh);
    return fresh;
  }
  return existing;
}

export function checkRateLimit(userId: string): RateLimitResult {
  const state = getState(userId);

  if (state.count >= HARD_LIMIT) {
    const retryAfterMs = WINDOW_MS - (Date.now() - state.windowStart);
    return { allowed: false, currentCount: state.count, retryAfterMs };
  }

  return { allowed: true, currentCount: state.count };
}

export function incrementCount(userId: string): void {
  const state = getState(userId);
  state.count += 1;
}

export function isApproachingLimit(userId: string): boolean {
  const state = getState(userId);
  return state.count >= SOFT_LIMIT;
}

export function getTimeUntilWindowReset(userId: string): number {
  const state = getState(userId);
  const elapsed = Date.now() - state.windowStart;
  return Math.max(0, WINDOW_MS - elapsed);
}

export function forceSetCount(userId: string, count: number): void {
  const state = getState(userId);
  state.count = count;
}

export function clearAllLimits(): void {
  store.clear();
}
