import type { ActivitySource, CompletionCandidate } from './rewardPreview';

export interface ActivityEventRecord {
  /** Globally unique completion identity; completion_id is its indexed immutable alias. */
  id: string;
  completion_id: string;
  owner_uid: string;
  source_type: ActivitySource;
  source_id: string;
  completed_at: string;
  day_key: string;
  policy_version: string;
  provenance: CompletionCandidate['evidence'];
  payload: string | null;
}
export interface RewardReceiptRecord {
  id: string;
  owner_uid: string;
  source_type: ActivitySource;
  completion_id: string;
  day_key: string;
  slot_index: number;
  policy_version: string;
  awarded_at: string;
}
export type Milestone = 5 | 10 | 15 | 20 | 25;
export interface MilestoneReceiptRecord { id: string; owner_uid: string; milestone: Milestone; }
