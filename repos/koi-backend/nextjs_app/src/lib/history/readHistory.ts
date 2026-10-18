import { db } from '@/lib/db';

export const HISTORY_MESSAGE_LIMIT = 200;
export interface HistoryMessage { id: string; sender: 'user' | 'ai'; text: string; at: Date; }
export interface HistoryConversation {
  id: string; title: string; createdAt: Date | null; earliestRetainedAt: Date;
  lastActivityAt: Date; active: boolean; retainedRecords: number; messages: HistoryMessage[];
}
export interface HistoryResult { conversations: HistoryConversation[]; truncated: boolean; unreadable: number; }
export class HistoryReadError extends Error {
  constructor(readonly kind: 'owner-changed' | 'locked') { super('History is unavailable.'); }
}
/** Read-only bounded view. No new store, key lifecycle, session selection, sync or write. */
export async function readOwnedHistory(owner: string, decryptOwned: (ciphertext: string, record: { id: string; conversationId: string }) => Promise<string>,
  options: { signal: AbortSignal; isCurrentOwner: () => boolean; allowLockedMetadata?: boolean }): Promise<HistoryResult> {
  const guard = () => {
    if (options.signal.aborted) throw new DOMException('History read cancelled.', 'AbortError');
    if (!owner.trim() || !options.isCurrentOwner()) throw new HistoryReadError('owner-changed');
  };
  guard();
  const { rows, header } = await db.transaction('r', db.messages, db.conversations, async () => ({
    rows: await db.messages.orderBy('timestamp').reverse().filter(row => row.ownerUid === owner)
      .limit(HISTORY_MESSAGE_LIMIT + 1).toArray(),
    header: await db.conversations.get(owner),
  }));
  guard();
  const groups = new Map<string, HistoryConversation>();
  let unreadable = 0;
  // Read oldest first within the bounded retained window; titles quote actual user input.
  for (const row of rows.slice(0, HISTORY_MESSAGE_LIMIT).reverse()) {
    guard();
    if (!row.conversationId || !row.id || !['user', 'ai'].includes(row.sender)
      || !(row.timestamp instanceof Date) || !Number.isFinite(+row.timestamp)) { unreadable++; continue; }
    if (typeof row.content !== 'string' || !row.content.startsWith('v1:PBKDF2:') || row.content.length > 100000) { unreadable++; continue; }
    let group = groups.get(row.conversationId);
    if (!group) {
      group = { id: row.conversationId, title: '', createdAt: header?.conversationId === row.conversationId && header.createdAt instanceof Date && Number.isFinite(+header.createdAt) ? header.createdAt : null,
        earliestRetainedAt: row.timestamp, lastActivityAt: row.timestamp, active: header?.conversationId === row.conversationId, retainedRecords: 0, messages: [] };
      groups.set(row.conversationId, group);
    }
    group.retainedRecords++;
    group.lastActivityAt = row.timestamp;
    let text: string;
    try { text = await decryptOwned(row.content, row); } catch { guard(); unreadable++; continue; }
    guard();
    if (typeof text !== 'string' || text.length > 64000) { unreadable++; continue; }
    if (!group.title && row.sender === 'user' && text.trim()) group.title = text.trim().slice(0, 80);
    group.messages.push({ id: row.id, sender: row.sender, text, at: row.timestamp });
  }
  guard();
  if (rows.length && ![...groups.values()].some(c => c.messages.length) && unreadable && !options.allowLockedMetadata) throw new HistoryReadError('locked');
  return { conversations: [...groups.values()].sort((a, b) => +b.lastActivityAt - +a.lastActivityAt),
    truncated: rows.length > HISTORY_MESSAGE_LIMIT, unreadable };
}

/** Search only this in-memory, current-owner, already decrypted window. No persistence/index. */
export function searchHistory(history: HistoryResult, query: string): HistoryConversation[] {
  const term = query.trim().slice(0, 120).normalize('NFKC').toLocaleLowerCase();
  return history.conversations.filter(c => !term || c.messages.some(m => m.text.normalize('NFKC').toLocaleLowerCase().includes(term)));
}
