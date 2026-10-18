import { db } from '@/lib/db';
import type { HistoryMessage } from './readHistory';
import { OwnedDecryptFailed, withOwnedDecryptor } from './ownedDecryptor';

export const ARCHIVE_LIST_LIMIT = 100;
export interface ArchivedConversationView {
  conversationId: string; locked: boolean; title: string;
  createdAt: Date; lastActiveAt: Date; archivedAt: Date;
  /** Null when the row is locked: the count lives inside the ciphertext. */
  messageCount: number | null; messages: HistoryMessage[];
}
export interface ArchiveReadResult {
  status: 'ready' | 'locked' | 'unavailable'; conversations: ArchivedConversationView[]; truncated: boolean;
}

/** Owner-scoped, bounded and read-only. Titles quote the first saved user message, decrypted in memory only. */
export async function readArchivedConversations(uid: string, signal: AbortSignal): Promise<ArchiveReadResult> {
  let rows;
  try {
    rows = (await db.conversationArchive.where('uid').equals(uid).toArray())
      .filter(row => row.uid === uid).sort((a, b) => +b.archivedAt - +a.archivedAt);
  } catch { return { status: 'unavailable', conversations: [], truncated: false }; }
  const truncated = rows.length > ARCHIVE_LIST_LIMIT;
  rows = rows.slice(0, ARCHIVE_LIST_LIMIT);
  const lockedView = (row: typeof rows[number]): ArchivedConversationView => ({ conversationId: row.conversationId, locked: true, title: '',
    createdAt: row.createdAt, lastActiveAt: row.lastActiveAt, archivedAt: row.archivedAt, messageCount: null, messages: [] });
  const result = await withOwnedDecryptor(uid, signal, async decryptOwned => {
    const views: ArchivedConversationView[] = [];
    for (const row of rows) {
      if (!row.encryptedState) { views.push({ ...lockedView(row), locked: false, messageCount: 0 }); continue; }
      let messages: HistoryMessage[];
      try {
        const recovered = JSON.parse(await decryptOwned(row.encryptedState));
        const saved = recovered?.snapshot?.messages;
        if (recovered?.ownerUid !== uid || !Array.isArray(saved) || saved.some((m: { conversationId?: string }) => m?.conversationId !== row.conversationId)) throw new OwnedDecryptFailed();
        messages = saved.filter((m: { sender?: string; content?: unknown }) => (m.sender === 'user' || m.sender === 'ai') && typeof m.content === 'string' && m.content)
          .map((m: { id: string; sender: 'user' | 'ai'; content: string; timestamp: string }) => ({ id: m.id, sender: m.sender, text: m.content, at: new Date(m.timestamp) }));
      } catch (error) {
        if (error instanceof OwnedDecryptFailed || error instanceof SyntaxError) { views.push(lockedView(row)); continue; }
        throw error;
      }
      views.push({ conversationId: row.conversationId, locked: false, createdAt: row.createdAt, lastActiveAt: row.lastActiveAt, archivedAt: row.archivedAt,
        title: messages.find(m => m.sender === 'user' && m.text.trim())?.text.trim().slice(0, 80) ?? '', messageCount: messages.length, messages });
    }
    return views;
  });
  if (result.status === 'ready') return { status: 'ready', conversations: result.value, truncated };
  return { status: result.status, conversations: result.status === 'locked' && result.reason !== 'owner-unverified' ? rows.map(lockedView) : [], truncated };
}
