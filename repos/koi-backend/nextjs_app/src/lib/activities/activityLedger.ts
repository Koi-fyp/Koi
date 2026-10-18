import { onAuthStateChanged } from 'firebase/auth';
import type { Transaction } from 'dexie';
import { auth } from '@/lib/firebase';
import { db, type KoiDatabase } from '@/lib/db';
import { isSupportedCiphertext } from '@/lib/data-portability/backupDraft';
import { karachiDay, previewReward, REWARD_POLICY, type CompletionCandidate } from './rewardPreview';
import type { ActivityEventRecord, Milestone, RewardReceiptRecord } from './activityTypes';

export const MILESTONES: readonly Milestone[] = [5, 10, 15, 20, 25];
export class ActivityLedgerError extends Error {
  constructor(readonly reason: 'owner-changed' | 'invalid-completion' | 'invalid-payload' | 'identity-conflict' | 'inconsistent-ledger') {
    super(`Activity could not be saved: ${reason}.`);
  }
}
function assertOwner(owner: string) {
  if (!owner || auth?.currentUser?.uid !== owner) throw new ActivityLedgerError('owner-changed');
}
const receiptKey = (owner: string, source: string, day: string) => JSON.stringify([owner, source, day]);
const milestoneKey = (owner: string, milestone: Milestone) => JSON.stringify([owner, milestone]);
export type ActivityReceipt = {
  event: ActivityEventRecord;
  reward: RewardReceiptRecord | null;
  outcome: 'awarded' | 'duplicate' | 'daily-cap' | 'board-full';
};

/** Internal writer for verified producers, NOT authority to infer completion from a button/SSE event.
 * Encrypt before calling. No crypto, network, source writes, sync queue, or import/export inside it.
 */
export function createActivityLedger(database: KoiDatabase = db) {
  async function record(candidate: CompletionCandidate, payload: string | null): Promise<ActivityReceipt> {
    const owner = candidate.ownerUid;
    assertOwner(owner);
    if (!previewReward(owner, candidate, []).eligible) throw new ActivityLedgerError('invalid-completion');
    if ((candidate.source === 'check_in' && payload === null) || (payload !== null && !isSupportedCiphertext(payload))) throw new ActivityLedgerError('invalid-payload');
    // Copy scalar allowlisted evidence only; never persist arbitrary notes/ratings in provenance.
    const evidence = candidate.evidence;
    if (candidate.source === 'breathing' && (evidence.endReason !== 'completed' || evidence.measurement !== 'client-measured' || !Number.isFinite(evidence.durationMs) || evidence.durationMs! < 48000)) throw new ActivityLedgerError('invalid-completion');
    for (const key of ['persisted', 'recordedUnderPolicy', 'explicit', 'userInitiated', 'consented', 'cancelled', 'crisisInterrupted'] as const) {
      if (evidence[key] !== undefined && typeof evidence[key] !== 'boolean') throw new ActivityLedgerError('invalid-completion');
    }
    for (const key of ['persistedExchanges', 'completedCycles', 'totalCycles'] as const) {
      if (evidence[key] !== undefined && (!Number.isSafeInteger(evidence[key]) || evidence[key]! < 0)) throw new ActivityLedgerError('invalid-completion');
    }
    if (!/^\d{4}-/.test(candidate.completedAt)) throw new ActivityLedgerError('invalid-completion');
    const provenance = Object.fromEntries(['persisted', 'recordedUnderPolicy', 'explicit', 'persistedExchanges', 'userInitiated', 'consented', 'completedCycles', 'totalCycles', 'cancelled', 'crisisInterrupted', 'durationMs', 'endReason', 'measurement']
      .filter(key => evidence[key as keyof typeof evidence] !== undefined)
      .map(key => [key, evidence[key as keyof typeof evidence]])) as CompletionCandidate['evidence'];
    const event: ActivityEventRecord = {
      id: candidate.completionId, completion_id: candidate.completionId, owner_uid: owner,
      source_type: candidate.source, source_id: candidate.sourceId, completed_at: candidate.completedAt,
      day_key: karachiDay(candidate.completedAt), policy_version: REWARD_POLICY, provenance, payload,
    };
    let transaction: Transaction | undefined;
    let ownerChanged = false;
    const unsubscribe = onAuthStateChanged(auth!, user => {
      if (user?.uid !== owner) { ownerChanged = true; transaction?.abort(); }
    });
    try {
      return await database.transaction('rw', database.activityEvents, database.rewardReceipts, database.milestoneReceipts, async tx => {
        transaction = tx;
        const guard = () => { if (ownerChanged) throw new ActivityLedgerError('owner-changed'); assertOwner(owner); };
        guard();
        // Catch only the expected uniqueness collision INSIDE the transaction, preserving its validity.
        let duplicate = false;
        await database.activityEvents.add(event).catch(error => {
          if (error?.name !== 'ConstraintError') throw error;
          duplicate = true;
        });
        guard();
        if (duplicate) {
          const existing = await database.activityEvents.where('[owner_uid+source_type+completion_id]').equals([owner, event.source_type, event.completion_id]).first();
          guard();
          if (!existing || existing.owner_uid !== owner || existing.source_type !== event.source_type || existing.source_id !== event.source_id) throw new ActivityLedgerError('identity-conflict');
          const rewards = await database.rewardReceipts.where('owner_uid').equals(owner).toArray();
          guard();
          return { event: existing, reward: rewards.find(receipt => receipt.source_type === existing.source_type && receipt.completion_id === existing.id) ?? null, outcome: 'duplicate' as const };
        }
        const receipts = await database.rewardReceipts.where('owner_uid').equals(owner).sortBy('slot_index');
        guard();
        if (receipts.length > 25 || receipts.some((receipt, index) => receipt.slot_index !== index + 1)) throw new ActivityLedgerError('inconsistent-ledger');
        const daily = await database.rewardReceipts.where('[owner_uid+source_type+day_key]').equals([owner, event.source_type, event.day_key]).first();
        guard();
        if (daily) return { event, reward: null, outcome: 'daily-cap' as const };
        if (receipts.length === 25) return { event, reward: null, outcome: 'board-full' as const };
        const reward: RewardReceiptRecord = {
          id: receiptKey(owner, event.source_type, event.day_key), owner_uid: owner, source_type: event.source_type,
          completion_id: event.id, day_key: event.day_key, slot_index: receipts.length + 1,
          policy_version: REWARD_POLICY, awarded_at: new Date().toISOString(),
        };
        await database.rewardReceipts.add(reward);
        guard();
        if (MILESTONES.includes(reward.slot_index as Milestone)) {
          const milestone = reward.slot_index as Milestone;
          await database.milestoneReceipts.add({ id: milestoneKey(owner, milestone), owner_uid: owner, milestone });
          guard();
        }
        return { event, reward, outcome: 'awarded' as const };
      });
    } catch (error) {
      if (ownerChanged || auth?.currentUser?.uid !== owner) throw new ActivityLedgerError('owner-changed');
      // Unexpected failures abort every row. Do not retry by partially applying a receipt.
      throw error;
    } finally { unsubscribe(); }
  }
  async function read(owner: string) {
    assertOwner(owner);
    const result = await database.transaction('r', database.activityEvents, database.rewardReceipts, database.milestoneReceipts, async () => {
      const events = await database.activityEvents.where('owner_uid').equals(owner).toArray(); assertOwner(owner);
      const rewards = await database.rewardReceipts.where('owner_uid').equals(owner).sortBy('slot_index'); assertOwner(owner);
      const milestones = await database.milestoneReceipts.where('owner_uid').equals(owner).sortBy('milestone'); assertOwner(owner);
      if (rewards.length > 25 || rewards.some((receipt, index) => receipt.slot_index !== index + 1 || receipt.policy_version !== REWARD_POLICY || !events.some(event => event.id === receipt.completion_id && event.source_type === receipt.source_type && event.day_key === receipt.day_key))
        || milestones.some(receipt => !MILESTONES.includes(receipt.milestone) || receipt.milestone > rewards.length)) throw new ActivityLedgerError('inconsistent-ledger');
      return { events, rewards, milestones };
    });
    assertOwner(owner);
    return result;
  }
  return { record, read };
}
export const activityLedger = createActivityLedger();
