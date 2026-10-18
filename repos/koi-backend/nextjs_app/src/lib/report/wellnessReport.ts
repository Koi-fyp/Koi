import { karachiDay } from '@/lib/activities/rewardPreview';
import type { ActivityEventRecord, MilestoneReceiptRecord, RewardReceiptRecord } from '@/lib/activities/activityTypes';
import type { SavedCheckIn } from '@/lib/checkins/checkInService';

export const REPORT_DISCLAIMER = 'Self-reported and app-activity data only; not a clinical assessment.';
/** Per-conversation metadata from saved rows; no message content. */
export interface ConversationActivity { conversationId: string; dayKeys: ReadonlySet<string>; }
export interface RatingSummary { min: number; max: number; average: number; }
export interface WellnessReport {
  from: string; to: string;
  checkIns: SavedCheckIn[];
  ratings: Record<'mood' | 'connection' | 'energy', RatingSummary> | null;
  activity: { checkIns: number; breathingSessions: number; completedConversations: number };
  piecesEarned: number; milestones: number[]; conversations: string[];
}
const DAY = /^\d{4}-\d{2}-\d{2}$/;
const inRange = (day: string, from: string, to: string) => day >= from && day <= to;

/** Built only from saved local records for an inclusive Asia/Karachi day range. No crisis, risk or inferred data. */
export function buildWellnessReport(input: {
  from: string; to: string; entries: readonly SavedCheckIn[]; events: readonly ActivityEventRecord[];
  rewards: readonly RewardReceiptRecord[]; milestones: readonly MilestoneReceiptRecord[]; conversations: readonly ConversationActivity[];
}): WellnessReport {
  if (!DAY.test(input.from) || !DAY.test(input.to) || input.from > input.to) throw new Error('A valid date range is required.');
  const { from, to } = input;
  const checkIns = input.entries.filter(entry => inRange(karachiDay(entry.completedAt), from, to));
  const summarize = (key: 'mood' | 'connection' | 'energy'): RatingSummary => {
    const values = checkIns.map(entry => entry[key]);
    return { min: Math.min(...values), max: Math.max(...values), average: Math.round(values.reduce((a, b) => a + b, 0) / values.length * 10) / 10 };
  };
  const events = input.events.filter(event => inRange(event.day_key, from, to));
  return {
    from, to, checkIns,
    ratings: checkIns.length ? { mood: summarize('mood'), connection: summarize('connection'), energy: summarize('energy') } : null,
    activity: { checkIns: events.filter(e => e.source_type === 'check_in').length, breathingSessions: events.filter(e => e.source_type === 'breathing').length,
      completedConversations: new Set(events.filter(e => e.source_type === 'conversation').map(e => e.source_id)).size },
    piecesEarned: input.rewards.filter(reward => inRange(reward.day_key, from, to)).length,
    milestones: input.milestones.map(receipt => receipt.milestone).sort((a, b) => a - b),
    conversations: input.conversations.filter(c => [...c.dayKeys].some(day => inRange(day, from, to))).map(c => c.conversationId),
  };
}
