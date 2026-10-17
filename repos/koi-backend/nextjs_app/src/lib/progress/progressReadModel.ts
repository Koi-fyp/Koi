import { db, type JigsawProgressRecord, type MessageRecord } from '../db';

export interface ProgressSummary {
  recordedProgress: JigsawProgressRecord | null;
  completedExchanges: number;
  conversationsWithReplies: number;
  lastCompletedAt: Date | null;
}

const validDate = (value: unknown): value is Date => value instanceof Date && Number.isFinite(value.getTime());
const counter = (value: unknown): value is number => Number.isSafeInteger(value) && (value as number) >= 0;
const encrypted = (row: MessageRecord) => typeof row.content === 'string' && row.content.startsWith('v1:PBKDF2:');

/** Completion evidence only: neither text interpretation nor a new reward/eligibility policy. */
export function summarizeCompletedExchanges(uid: string, rows: ReadonlyArray<MessageRecord>) {
  const owned = rows.filter(row => row.ownerUid === uid && encrypted(row) && row.conversationId);
  const users = new Map(owned.filter(row => row.sender === 'user').map(row => [row.id, row]));
  const completed = new Map<string, { conversationId: string; timestamp: Date }>();
  const replies = owned.filter(row => row.sender === 'ai' && validDate(row.timestamp))
    .slice().sort((left, right) => left.timestamp.getTime() - right.timestamp.getTime() || left.id.localeCompare(right.id));
  for (const reply of replies) {
    const user = reply.replyTo ? users.get(reply.replyTo) : undefined;
    if (!user || user.conversationId !== reply.conversationId) continue;
    // A repeated/differently-ID'd assistant row for the same user turn is still one exchange.
    const source = JSON.stringify([reply.conversationId, user.id]);
    if (!completed.has(source)) completed.set(source, { conversationId: reply.conversationId, timestamp: reply.timestamp });
  }
  const entries = [...completed.values()];
  return {
    completedExchanges: entries.length,
    conversationsWithReplies: new Set(entries.map(entry => entry.conversationId)).size,
    lastCompletedAt: entries.reduce<Date | null>((latest, entry) => !latest || entry.timestamp > latest ? entry.timestamp : latest, null),
  };
}

function validateRecordedProgress(uid: string, row: JigsawProgressRecord | undefined): JigsawProgressRecord | null {
  if (!row) return null;
  const sources = row.pieces_by_source;
  if (row.uid !== uid || !counter(row.jigsaw_pieces) || !sources
    || ![sources.conversations, sources.check_ins, sources.breathing, sources.tasks, sources.bonuses].every(counter)
    || !Array.isArray(row.milestones_reached) || !row.milestones_reached.every(counter)
    || !validDate(row.last_updated)) throw new Error('Stored progress is unavailable.');
  // Preserve recorded totals; do not repair/recompute awards under an unapproved policy.
  return row;
}

/** Read-only existing stores. Never decrypt message bodies, award points, sync, or change schemas. */
export async function readProgress(uid: string): Promise<ProgressSummary> {
  if (!uid.trim()) throw new Error('A progress owner is required.');
  return db.transaction('r', db.jigsawProgress, db.messages, async () => {
    const recordedProgress = validateRecordedProgress(uid, await db.jigsawProgress.get(uid));
    const rows = await db.messages.filter(row => row.ownerUid === uid).toArray();
    return { recordedProgress, ...summarizeCompletedExchanges(uid, rows) };
  });
}
