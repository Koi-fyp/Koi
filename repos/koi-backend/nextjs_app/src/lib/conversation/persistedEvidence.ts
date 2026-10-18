import { db, type MessageRecord } from '../db';

/** Newest saved user turn plus its saved post-done reply. Never derived from session memory or SSE indexes. */
export interface QualifyingPair {
  userMessageId: string; assistantMessageId: string;
  /** Newest owned row in the conversation; the completion identity is bound to it. */
  lastPersistedMessageId: string;
  persistedExchanges: number;
}
export interface PersistedTurnEvidence { pair: QualifyingPair | null; hasUnresolvedHandoff: boolean; }

async function ownedRows(uid: string, conversationId: string): Promise<MessageRecord[]> {
  const rows = await db.messages.where('conversationId').equals(conversationId).sortBy('timestamp');
  return rows.filter(row => row.ownerUid === uid && row.conversationId === conversationId);
}
export function qualifyingPair(rows: readonly MessageRecord[]): QualifyingPair | null {
  const replies = new Map(rows.filter(row => row.sender === 'ai' && row.done_seen === true && row.replyTo).map(row => [row.replyTo!, row]));
  const users = rows.filter(row => row.sender === 'user');
  const newestUser = users[users.length - 1];
  const reply = newestUser && replies.get(newestUser.id);
  if (!reply) return null;
  return { userMessageId: newestUser.id, assistantMessageId: reply.id, lastPersistedMessageId: rows[rows.length - 1].id,
    persistedExchanges: users.filter(user => replies.has(user.id)).length };
}
/** Open while the newest completed AI row carries handoff_open; only a later completed turn without a handoff clears it. */
export function unresolvedHandoff(rows: readonly MessageRecord[]): boolean {
  return [...rows].reverse().find(row => row.sender === 'ai')?.handoff_open === true;
}
export async function getQualifyingPair(uid: string, conversationId: string): Promise<QualifyingPair | null> {
  return qualifyingPair(await ownedRows(uid, conversationId));
}
export async function readPersistedTurnEvidence(uid: string, conversationId: string): Promise<PersistedTurnEvidence> {
  const rows = await ownedRows(uid, conversationId);
  return { pair: qualifyingPair(rows), hasUnresolvedHandoff: unresolvedHandoff(rows) };
}
export class CompletionLeaseError extends Error {
  constructor(readonly reason: 'busy' | 'pending' | 'unavailable') { super(`Conversation completion unavailable: ${reason}.`); }
}
