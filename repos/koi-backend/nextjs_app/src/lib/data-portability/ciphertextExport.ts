import { db } from '@/lib/db';
import { isSupportedCiphertext } from './backupDraft';

export const DATA_EXPORT_MAX_RECORDS = 200;
export const DATA_EXPORT_MAX_BYTES = 2 * 1024 * 1024;
export interface ExportAccess { currentOwner: () => string | null; signal: AbortSignal; }
export interface CiphertextDataExport {
  kind: 'koi-ciphertext-data-export'; formatVersion: 1; ownerUid: string; exportedAt: string;
  scope: 'owner-tagged-device-local-records'; consistency: 'single-readonly-database-transaction';
  restorationSupported: false; decryptionVerified: false; manifestAuthenticated: false; originalKeyRequiredToDecrypt: true;
  counts: { messages: number; conversationSnapshots: number };
  messages: Array<{ id: string; ownerUid: string; conversationId: string; sender: 'user' | 'ai'; timestamp: string; replyTo?: string; ciphertext: string }>;
  conversationSnapshots: Array<{ ownerUid: string; conversationId: string; createdAt: string; lastActiveAt: string; revision: number; ciphertext: string }>;
}
export class DataExportError extends Error {
  constructor(readonly reason: 'owner-changed' | 'cancelled' | 'limit' | 'invalid-record' | 'snapshot-unavailable' | 'empty') {
    super({
      'owner-changed': 'Your account changed. Prepare a new export for the current account.',
      cancelled: 'Export cancelled. No records were changed.',
      limit: 'This export supports at most 200 records and 2 MiB. No partial file was prepared.',
      'invalid-record': 'Some local records have unsupported metadata or encrypted content. No file was prepared.',
      'snapshot-unavailable': 'The encrypted conversation snapshot is not available yet. Return to Chat, then retry.',
      empty: 'No owner-tagged encrypted conversation records are available to export on this device.',
    }[reason]);
  }
}
export function assertExportOwner(ownerUid: string, access: ExportAccess) {
  if (access.signal.aborted) throw new DataExportError('cancelled');
  if (!ownerUid || ownerUid.length > 128 || access.currentOwner() !== ownerUid) throw new DataExportError('owner-changed');
}
const identifier = (v: unknown): v is string => typeof v === 'string' && !!v.trim() && v.length <= 160 && !/[\u0000-\u001f\u007f]/.test(v);
const validDate = (v: unknown): v is Date => v instanceof Date && Number.isFinite(+v);

/** Copy ciphertext only. No keys, crypto context, decryption, checkpoint, sync, migration or writes. */
export async function readCiphertextExport(ownerUid: string, access: ExportAccess): Promise<CiphertextDataExport> {
  assertExportOwner(ownerUid, access);
  const captured = await db.transaction('r', db.messages, db.conversations, async () => {
    const messages = await db.messages.orderBy('timestamp').filter(r => r.ownerUid === ownerUid).limit(DATA_EXPORT_MAX_RECORDS + 1).toArray();
    const snapshot = await db.conversations.get(ownerUid);
    return { messages, snapshot };
  });
  assertExportOwner(ownerUid, access);
  if (captured.messages.length + (captured.snapshot ? 1 : 0) > DATA_EXPORT_MAX_RECORDS) throw new DataExportError('limit');
  const messages: CiphertextDataExport['messages'] = captured.messages.map(row => {
    if (row.ownerUid !== ownerUid || !identifier(row.id) || !identifier(row.conversationId) || !['user','ai'].includes(row.sender)
      || !validDate(row.timestamp) || !isSupportedCiphertext(row.content) || (row.replyTo !== undefined && !identifier(row.replyTo))) throw new DataExportError('invalid-record');
    // Deliberate allowlist: exclude plaintext emotion/risk scores, extra fields, profiles and credentials.
    return { id: row.id, ownerUid, conversationId: row.conversationId, sender: row.sender, timestamp: row.timestamp.toISOString(),
      ...(row.replyTo !== undefined ? { replyTo: row.replyTo } : {}), ciphertext: row.content };
  });
  const conversationSnapshots: CiphertextDataExport['conversationSnapshots'] = [];
  const row = captured.snapshot;
  if (row) {
    if (!row.encryptedState) throw new DataExportError('snapshot-unavailable');
    if (row.uid !== ownerUid || !identifier(row.conversationId) || !validDate(row.createdAt) || !validDate(row.lastActiveAt)
      || !Number.isSafeInteger(row.revision) || row.revision < 0 || !isSupportedCiphertext(row.encryptedState)) throw new DataExportError('invalid-record');
    conversationSnapshots.push({ ownerUid, conversationId: row.conversationId, createdAt: row.createdAt.toISOString(), lastActiveAt: row.lastActiveAt.toISOString(), revision: row.revision, ciphertext: row.encryptedState });
  }
  if (!messages.length && !conversationSnapshots.length) throw new DataExportError('empty');
  const result: CiphertextDataExport = { kind:'koi-ciphertext-data-export', formatVersion:1, ownerUid, exportedAt:new Date().toISOString(),
    scope:'owner-tagged-device-local-records', consistency:'single-readonly-database-transaction',
    restorationSupported:false, decryptionVerified:false, manifestAuthenticated:false, originalKeyRequiredToDecrypt:true,
    counts:{messages:messages.length,conversationSnapshots:conversationSnapshots.length}, messages, conversationSnapshots };
  serializeCiphertextExport(result);
  assertExportOwner(ownerUid, access);
  return result;
}
export function serializeCiphertextExport(value: CiphertextDataExport): string {
  const text = JSON.stringify(value, null, 2);
  if (new TextEncoder().encode(text).byteLength > DATA_EXPORT_MAX_BYTES) throw new DataExportError('limit');
  return text;
}
