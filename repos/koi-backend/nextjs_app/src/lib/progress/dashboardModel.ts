import { karachiDay } from '@/lib/activities/rewardPreview';
import type { ActivityEventRecord } from '@/lib/activities/activityTypes';
import type { SavedCheckIn } from '@/lib/checkins/checkInService';

/** Read model over saved records only: no inference, scoring, streaks or clinical interpretation. */
export type RangeKey = '7d' | '30d' | '90d' | 'all';
export const RANGES: ReadonlyArray<{ key: RangeKey; label: string; days: number | null }> = [
  { key: '7d', label: '7 days', days: 7 }, { key: '30d', label: '30 days', days: 30 },
  { key: '90d', label: '90 days', days: 90 }, { key: 'all', label: 'All time', days: null },
];
const DAY_MS = 86_400_000;

export function rangeStart(range: RangeKey, now = Date.now()): number | null {
  const days = RANGES.find(r => r.key === range)?.days ?? null;
  return days === null ? null : now - days * DAY_MS;
}
export function filterCheckIns(entries: readonly SavedCheckIn[], range: RangeKey, now = Date.now()) {
  const start = rangeStart(range, now);
  return entries.filter(entry => { const at = Date.parse(entry.completedAt); return Number.isFinite(at) && at <= now && (start === null || at >= start); });
}
/** Saved activity records per Asia/Karachi calendar day. */
export function activityDayCounts(events: readonly Pick<ActivityEventRecord, 'day_key'>[]) {
  const days = new Map<string, number>();
  for (const event of events) days.set(event.day_key, (days.get(event.day_key) ?? 0) + 1);
  return days;
}
export interface HeatmapCell { day: string; count: number; future: boolean; }
/** Weeks (Mon..Sun columns) ending with the current Karachi week; Karachi has no DST, so fixed-day steps are exact. */
export function heatmapWeeks(days: ReadonlyMap<string, number>, weeks = 13, now = Date.now()): HeatmapCell[][] {
  const today = karachiDay(new Date(now).toISOString());
  const weekday = (key: string) => (new Date(`${key}T00:00:00Z`).getUTCDay() + 6) % 7; // Monday = 0
  const monday = Date.parse(`${today}T00:00:00Z`) - weekday(today) * DAY_MS;
  const columns: HeatmapCell[][] = [];
  for (let w = weeks - 1; w >= 0; w--) {
    const column: HeatmapCell[] = [];
    for (let d = 0; d < 7; d++) {
      const day = new Date(monday - w * 7 * DAY_MS + d * DAY_MS).toISOString().slice(0, 10);
      column.push({ day, count: days.get(day) ?? 0, future: day > today });
    }
    columns.push(column);
  }
  return columns;
}
export interface DashboardCounts {
  completedExchanges: number; conversations: number; completedConversations: number;
  checkIns: number; breathingSessions: number; pieces: number; milestones: number;
}
export function dashboardCounts(input: {
  completedExchanges: number; conversations: number;
  events: readonly Pick<ActivityEventRecord, 'source_type' | 'source_id'>[]; rewards: readonly unknown[]; milestones: readonly unknown[];
}): DashboardCounts {
  const of = (source: ActivityEventRecord['source_type']) => input.events.filter(event => event.source_type === source);
  return { completedExchanges: input.completedExchanges, conversations: input.conversations,
    completedConversations: new Set(of('conversation').map(event => event.source_id)).size,
    checkIns: of('check_in').length, breathingSessions: of('breathing').length,
    pieces: input.rewards.length, milestones: input.milestones.length };
}
