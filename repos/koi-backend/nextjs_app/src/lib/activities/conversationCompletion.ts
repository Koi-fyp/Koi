import { completionHash } from './breathingActivity';

/** Proposed shared-owner read/lease output. No current protected producer implements this yet. */
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
// Deliberately no runtime writer: current session drops earlier handoff events on next send.
// A reviewed lease must attest sticky acknowledged-resolution state before invoking the ledger.
