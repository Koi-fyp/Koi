import type { ChatServerEvent } from './chatContract';

/** Candidate event names only; their v1.1 payload contract is not verified. */
export type V11FixtureEventName = 'transcript' | 'risk' | 'done.risk';
export interface V11FixtureEvent { event: V11FixtureEventName; data: Record<string, unknown>; }

const enabled = () => process.env.NODE_ENV !== 'production' && process.env.NEXT_PUBLIC_KOI_V11_FIXTURE_EVENTS === 'true';

/** Offline contract fixture guard. This is deliberately not wired into the live v1 transport. */
export function parseV11FixtureEvent(name: string, raw: unknown): V11FixtureEvent | null {
  if (!enabled() || !['transcript', 'risk', 'done.risk'].includes(name)) return null;
  let value: unknown = raw;
  if (typeof raw === 'string') {
    try { value = JSON.parse(raw); } catch { return null; }
  }
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  // Keep the payload opaque until Ahmad publishes an authoritative schema.
  return { event: name as V11FixtureEventName, data: value as Record<string, unknown> };
}

/** The current Web UI enables only text; other allowed combinations are explicit but unavailable. */
export const INPUT_MODE_STATUS = {
  text: { allowed: true, enabled: true },
  audio: { allowed: true, enabled: false },
  'text+video': { allowed: true, enabled: false },
  'audio+video': { allowed: true, enabled: false },
} as const;

// Compile-time guard against accidentally routing candidate events through the v1 event union.
type _V1HasNoV11Events = Extract<ChatServerEvent['event'], V11FixtureEventName> extends never ? true : never;
const _v1Isolation: _V1HasNoV11Events = true;
void _v1Isolation;
