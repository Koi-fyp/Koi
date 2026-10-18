/** Review-stage file parser/dry-run only. Never an authorization, decryption or import writer. */
export const BACKUP_MAX_BYTES = 2 * 1024 * 1024;
export const BACKUP_MAX_RECORDS = 200;
export interface DraftRecord { source: 'messages' | 'conversations'; id: string; timestamp: string; ciphertext: string; }
export interface BackupDraft {
  kind: 'koi-backup-draft'; schemaVersion: 1; ownerUid: string; ownerBinding: string; createdAt: string; compatibility: 'same-owner-existing-key-only';
  sources: Array<'messages' | 'conversations'>; counts: { messages: number; conversations: number }; records: DraftRecord[];
}
export interface StructuralBackup { draft: BackupDraft; integrity: 'NOT VERIFIED'; decryption: 'NOT VERIFIED'; importAllowed: false; }
export type BackupErrorCode = 'file-type' | 'size' | 'read' | 'json' | 'schema' | 'version' | 'owner' | 'ciphertext' | 'duplicate' | 'record-limit';
const ERROR_TEXT: Record<BackupErrorCode, string> = {
  'file-type': 'Choose a KOI backup .json file. Text, CSV, PDF and document files are not supported.',
  size: 'The backup must contain data and be no larger than 2 MiB.',
  read: 'This file could not be read. Please choose it again.',
  json: 'This file does not contain valid JSON.',
  schema: 'This JSON is not a supported KOI backup envelope, or its fields are inconsistent.',
  version: 'This KOI backup version is not supported. Only draft schema version 1 can be previewed.',
  owner: 'This backup does not match the signed-in account. Matching accounts still require the original encryption key.',
  ciphertext: 'A record has missing or malformed encrypted content. It cannot be previewed.',
  duplicate: 'The backup repeats a record ID. Choose a consistent backup with unique record IDs.',
  'record-limit': 'This preview supports at most 200 records.',
};
export class BackupValidationError extends Error {
  constructor(readonly code: BackupErrorCode = 'schema') { super(`${ERROR_TEXT[code]} No records were changed.`); }
}
const fail = (code: BackupErrorCode = 'schema'): never => { throw new BackupValidationError(code); };
const object = (v: unknown): v is Record<string, unknown> => !!v && typeof v === 'object' && !Array.isArray(v) && Object.getPrototypeOf(v) === Object.prototype;
function exact(value: unknown, keys: string[]): asserts value is Record<string, unknown> {
  if (!object(value) || Object.keys(value).length !== keys.length || !Object.keys(value).every(k => keys.includes(k))) fail();
}
const date = (v: unknown): v is string => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(v)
  && Number.isFinite(Date.parse(v)) && new Date(v).toISOString() === v;
const binding = (v: unknown): v is string => typeof v === 'string' && /^[a-f0-9]{64}$/.test(v);
const source = (v: unknown): v is DraftRecord['source'] => v === 'messages' || v === 'conversations';
export function isSupportedCiphertext(v: unknown): v is string {
  if (typeof v !== 'string' || v.length > 100000) return false;
  const parts = v.split(':');
  if (parts.length !== 5 || parts[0] !== 'v1' || parts[1] !== 'PBKDF2') return false;
  try {
    const decoded = parts.slice(2).map(p => {
      if (!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(p)) fail();
      return atob(p).length;
    });
    return decoded[0] === 16 && decoded[1] === 12 && decoded[2] >= 16;
  } catch { return false; }
}
export function parseBackupDraft(text: string, currentOwnerUid: string, currentOwnerBinding: string): StructuralBackup {
  if (!currentOwnerUid || currentOwnerUid.length > 128 || !binding(currentOwnerBinding)) fail('owner');
  if (!text.length || new TextEncoder().encode(text).byteLength > BACKUP_MAX_BYTES) fail('size');
  let raw: unknown; try { raw = JSON.parse(text); } catch { return fail('json'); }
  exact(raw, ['kind','schemaVersion','ownerUid','ownerBinding','createdAt','compatibility','sources','counts','records']);
  if (raw.kind !== 'koi-backup-draft') fail();
  if (raw.schemaVersion !== 1) fail('version');
  if (raw.ownerUid !== currentOwnerUid || raw.ownerBinding !== currentOwnerBinding) fail('owner');
  if (raw.compatibility !== 'same-owner-existing-key-only' || !date(raw.createdAt)) fail();
  const sources=raw.sources;
  if (!Array.isArray(sources) || !sources.every(source) || new Set(sources).size !== sources.length) return fail();
  exact(raw.counts, ['messages','conversations']);
  const records=raw.records;
  if (!Array.isArray(records)) return fail();
  if (records.length > BACKUP_MAX_RECORDS) return fail('record-limit');
  const seen = new Set<string>(), counts = { messages: 0, conversations: 0 };
  for (const record of records) {
    exact(record, ['source','id','timestamp','ciphertext']);
    const recordSource=record.source;
    if (!source(recordSource) || !sources.includes(recordSource) || typeof record.id !== 'string'
      || !record.id.trim() || record.id.length > 160 || /[\u0000-\u001f\u007f]/.test(record.id) || !date(record.timestamp)) return fail();
    if (!isSupportedCiphertext(record.ciphertext)) fail('ciphertext');
    const key = JSON.stringify([record.source, record.id]);
    if (seen.has(key)) fail('duplicate'); seen.add(key); counts[recordSource]++;
  }
  if (raw.counts.messages !== counts.messages || raw.counts.conversations !== counts.conversations) fail();
  return { draft: raw as unknown as BackupDraft, integrity: 'NOT VERIFIED', decryption: 'NOT VERIFIED', importAllowed: false };
}
export async function readBackupDraft(file: Pick<File,'name'|'size'|'type'|'text'>, ownerUid: string, ownerBinding: string): Promise<StructuralBackup> {
  if (!file.name.toLowerCase().endsWith('.json') || !['','application/json','text/json'].includes(file.type)) fail('file-type');
  if (!Number.isSafeInteger(file.size) || file.size <= 0 || file.size > BACKUP_MAX_BYTES) fail('size');
  let text: string; try { text = await file.text(); } catch { return fail('read'); }
  return parseBackupDraft(text, ownerUid, ownerBinding);
}
export function previewDraftConflicts(parsed: StructuralBackup, existing: ReadonlyArray<DraftRecord>) {
  const saved = new Map(existing.map(r => [JSON.stringify([r.source,r.id]),r]));
  let duplicates = 0, conflicts = 0, newRecords = 0;
  for (const record of parsed.draft.records) {
    const prior = saved.get(JSON.stringify([record.source,record.id]));
    if (!prior) newRecords++;
    else if (prior.ciphertext === record.ciphertext && prior.timestamp === record.timestamp) duplicates++;
    else conflicts++;
  }
  return { newRecords, duplicates, conflicts, importAllowed: false as const,
    reason: 'Structure-only preview. Owner/key/integrity verification and approved transactional import are still required.' };
}

/** Joint owner supplies a nonmutating capability. No key lookup/creation or restoration here. */
export async function verifyDraftCiphertexts(parsed: StructuralBackup, access: {
  currentOwner: () => string | null; signal: AbortSignal;
  decryptExisting?: (ciphertext: string) => Promise<string>;
}) {
  const blocked = (reason: string) => ({ status: 'blocked' as const, reason, importAllowed: false as const });
  const current = () => !access.signal.aborted && access.currentOwner() === parsed.draft.ownerUid;
  if (!current()) return blocked('owner-changed-or-cancelled');
  if (!access.decryptExisting) return blocked('existing-key-unavailable');
  for (const record of parsed.draft.records) {
    if (!current()) return blocked('owner-changed-or-cancelled');
    try { await access.decryptExisting(record.ciphertext); }
    catch { return blocked('ciphertext-could-not-be-authenticated'); }
    if (!current()) return blocked('owner-changed-or-cancelled');
  }
  return { status: 'ciphertexts-verified' as const, records: parsed.draft.records.length,
    manifestIntegrity: 'NOT VERIFIED' as const, importAllowed: false as const };
}
