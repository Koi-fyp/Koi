import { auth } from '@/lib/firebase';
import { CompletionLeaseError } from '@/lib/conversation/persistedEvidence';
import { completionHash } from './breathingActivity';
import { activityLedger, type ActivityReceipt } from './activityLedger';
import { REWARD_POLICY } from './rewardPreview';

/** Read under PersistentConversation's completion lease from saved rows. */
export interface ConversationCompletionEvidence {
  ownerUid: string; conversationId: string; pending: boolean;
  lastPersistedMessageId: string | null; persistedExchanges: number;
  turnState: 'submitted' | 'partial' | 'failed' | 'cancelled' | 'done-unpersisted' | 'done-persisted';
  handoffState: 'unresolved' | 'resolved-or-absent' | 'unknown';
}
export function conversationCompletionEligible(owner: string, evidence: ConversationCompletionEvidence, explicit: boolean) {
  return explicit && !!owner && evidence.ownerUid === owner && !!evidence.conversationId && !evidence.pending
    && evidence.turnState === 'done-persisted' && evidence.handoffState === 'resolved-or-absent'
    && Number.isSafeInteger(evidence.persistedExchanges) && evidence.persistedExchanges >= 1 && !!evidence.lastPersistedMessageId;
}
export async function conversationCompletionId(owner: string, conversationId: string, lastPersistedMessageId: string) {
  return completionHash(`koi:conv:v1:${owner}:${conversationId}:${lastPersistedMessageId}`);
}
export interface CompletionLeaseHolder {
  readonly uid: string;
  withCompletionLease<T>(run: (evidence: ConversationCompletionEvidence) => Promise<T>): Promise<T>;
}
export type ConversationCompletionResult =
  | { status: 'saved'; outcome: ActivityReceipt['outcome']; completionId: string }
  | { status: 'rejected'; reason: 'busy' | 'pending' | 'no-pair' | 'unresolved-handoff' | 'owner-changed' | 'unavailable' };
const rejected = (reason: Extract<ConversationCompletionResult, { status: 'rejected' }>['reason']): ConversationCompletionResult => ({ status: 'rejected', reason });

/** The only conversation producer: one explicit user action. New Chat, navigation, Back and End never call it. */
export async function saveConversationCompletion(holder: CompletionLeaseHolder, ownerUid: string): Promise<ConversationCompletionResult> {
  if (!ownerUid || holder.uid !== ownerUid || auth?.currentUser?.uid !== ownerUid) return rejected('owner-changed');
  try {
    return await holder.withCompletionLease(async evidence => {
      if (evidence.pending) return rejected('pending');
      if (!evidence.lastPersistedMessageId || evidence.persistedExchanges < 1) return rejected('no-pair');
      if (evidence.handoffState !== 'resolved-or-absent') return rejected('unresolved-handoff');
      if (!conversationCompletionEligible(ownerUid, evidence, true)) return rejected('unavailable');
      const completionId = await conversationCompletionId(ownerUid, evidence.conversationId, evidence.lastPersistedMessageId);
      if (auth?.currentUser?.uid !== ownerUid) return rejected('owner-changed');
      const receipt = await activityLedger.record({ ownerUid, completionId, source: 'conversation', sourceId: evidence.conversationId,
        completedAt: new Date(Date.now()).toISOString(), policyVersion: REWARD_POLICY,
        evidence: { persisted: true, recordedUnderPolicy: true, explicit: true, persistedExchanges: evidence.persistedExchanges,
          cancelled: false, crisisInterrupted: false } }, null);
      return { status: 'saved', outcome: receipt.outcome, completionId };
    });
  } catch (error) {
    if (error instanceof CompletionLeaseError) return rejected(error.reason);
    if (auth?.currentUser?.uid !== ownerUid || (error as { reason?: string })?.reason === 'owner-changed') return rejected('owner-changed');
    return rejected('unavailable');
  }
}
