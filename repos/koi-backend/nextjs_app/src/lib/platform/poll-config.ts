/** Client-safe polling intervals. Fail-safe: non-integer input uses the default, out-of-range input is clamped. */
export function parsePollMs(raw: string | undefined, fallback: number, min: number, max: number): number {
  if (raw === undefined || !/^\d+$/.test(raw.trim())) return fallback;
  const value = Number(raw.trim());
  return Number.isSafeInteger(value) ? Math.min(max, Math.max(min, value)) : fallback;
}
/** Server stream: how often capabilities are re-checked (Firestore reads). */
export const accessPollMs = (raw = process.env.KOI_PLATFORM_ACCESS_POLL_MS) => parsePollMs(raw, 10000, 2000, 60000);
/** Navigation: how often /api/v1/me/capabilities is polled while visible. */
export const navPollMs = (raw = process.env.NEXT_PUBLIC_KOI_PLATFORM_NAV_POLL_MS) => parsePollMs(raw, 15000, 5000, 120000);
