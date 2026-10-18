import type { MessageRecord } from '../db';

/**
 * Cloud message copy for Firestore rules phase 1:
 * users/{uid}/conversations/{cid}/messages/{mid} with exactly these eight fields.
 * content is ciphertext only; local evidence (handoff_open, done_seen), ownership,
 * replyTo, companion state and audio never leave the device.
 */
export const MESSAGE_SYNC_FIELDS = ['id', 'conversationId', 'sender', 'content', 'timestamp', 'emotion', 'emotion_confidence', 'synced'] as const;
export interface MessageSyncPayload {
  id: string; conversationId: string; sender: 'user' | 'ai'; content: string;
  timestamp: Date; emotion: string; emotion_confidence: number; synced: boolean;
}
const OWNED_PATH = /^users\/([^/]+)\/conversations\/([^/]+)\/messages$/;
const LEGACY_PATH = /^conversations\/([^/]+)\/messages$/;

export function messageCollection(uid: string, conversationId: string) {
  return `users/${uid}/conversations/${conversationId}/messages`;
}
export function messageSyncPayload(record: Pick<MessageRecord, 'id' | 'conversationId' | 'sender' | 'content' | 'timestamp' | 'emotion' | 'emotion_confidence' | 'synced'>): MessageSyncPayload {
  const confidence = typeof record.emotion_confidence === 'number' && Number.isFinite(record.emotion_confidence)
    ? Math.min(1, Math.max(0, record.emotion_confidence)) : 0;
  const timestamp = record.timestamp instanceof Date ? record.timestamp : new Date(record.timestamp as unknown as string);
  return { id: record.id, conversationId: record.conversationId, sender: record.sender, content: record.content,
    timestamp, emotion: String(record.emotion ?? 'neutral').slice(0, 32), emotion_confidence: confidence, synced: record.synced === true };
}
export const isOwnedMessagePath = (collection: string) => OWNED_PATH.test(collection);
export const isLegacyMessagePath = (collection: string) => LEGACY_PATH.test(collection);
/** Restores the Firestore timestamp after the localStorage queue's JSON round-trip. */
export function reviveMessageData(collection: string, data: Record<string, unknown>): Record<string, unknown> {
  return isOwnedMessagePath(collection) ? { ...messageSyncPayload(data as unknown as MessageRecord) } : data;
}
/**
 * A queued item from the old root path, owned by the signed-in uid, becomes the owned path with the
 * exact payload. Items without that owner are left untouched (never adopted by another account).
 */
export function repathLegacyMessage<T extends { collection: string; docId: string; data: Record<string, unknown> }>(item: T, uid: string): T | null {
  const match = LEGACY_PATH.exec(item.collection);
  if (!match || !uid || item.data?.ownerUid !== uid) return null;
  const data = item.data as unknown as MessageRecord;
  if (data.conversationId !== match[1] || data.id !== item.docId) return null;
  return { ...item, collection: messageCollection(uid, match[1]), data: messageSyncPayload(data) as unknown as Record<string, unknown> };
}
