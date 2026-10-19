/** Transactional test double only. It is never imported into production routes. */
import type { PlatformStore, PlatformTransaction } from '../src/lib/platform/server/store';
import type { DraftDTO } from '../src/lib/platform/types';
const clone = <T>(value: T): T => JSON.parse(JSON.stringify(value));
export class MemoryPlatformStore implements PlatformStore {
  data = new Map<string, unknown>();
  writes: Array<{ collection: string; id: string; operation: string }> = [];
  private tail: Promise<unknown> = Promise.resolve();
  seed(collection: string, id: string, value: unknown) { this.data.set(`${collection}/${id}`, clone(value)); }
  read<T = any>(collection: string, id: string): T | null { const value = this.data.get(`${collection}/${id}`); return value === undefined ? null : clone(value) as T; }
  count(collection: string) { return [...this.data.keys()].filter(key => key.startsWith(collection + '/')).length; }
  transaction<T>(run: (tx: PlatformTransaction) => Promise<T>): Promise<T> {
    const work = this.tail.then(async () => {
      const snapshot = new Map(this.data);
      const writes: typeof this.writes = [];
      const readGuard = () => { if (writes.length) throw new Error('Firestore transactions require reads before writes'); };
      const tx: PlatformTransaction = {
        get: async <R>(collection: string, id: string) => { readGuard(); const value = snapshot.get(`${collection}/${id}`); return value === undefined ? null : clone(value) as R; },
        create: (collection, id, value) => { if (snapshot.has(`${collection}/${id}`)) throw new Error('Document already exists'); snapshot.set(`${collection}/${id}`, clone(value)); writes.push({ collection, id, operation: 'create' }); },
        set: (collection, id, value) => { snapshot.set(`${collection}/${id}`, clone(value)); writes.push({ collection, id, operation: 'set' }); },
        query: async <R>(collection: string, filters: Record<string, string>, after: string | null, limit: number) => {
          readGuard(); if (!Object.keys(filters).length || limit > 201) throw new Error('Scope required');
          return [...snapshot.entries()].filter(([key]) => key.startsWith(collection + '/')).map(([key, value]) => ({ key: key.slice(collection.length + 1), value: clone(value) as any }))
            .filter(row => (!after || row.key > after) && Object.entries(filters).every(([field, value]) => field.split('.').reduce((v, k) => v?.[k], row.value) === value))
            .sort((a, b) => a.key < b.key ? -1 : a.key > b.key ? 1 : 0).slice(0, limit).map(row => row.value as R);
        },
        drafts: async (org, owner, after, limit) => { readGuard(); return [...snapshot.entries()].filter(([key]) => key.startsWith('questionnaires/')).map(([, value]) => clone(value) as DraftDTO)
          .filter(value => value.organization_id === org && value.psychologist_uid === owner && (!after || value.id > after)).sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0).slice(0, limit); },
      };
      const result = await run(tx);
      this.data = snapshot; this.writes.push(...writes);
      return clone(result);
    });
    this.tail = work.catch(() => {});
    return work;
  }
}
export const testTime = new Date('2026-10-19T12:00:00Z');
export const actor = (uid = 'clinician_a') => ({ uid, authTime: +testTime / 1000 });
export function registered(store: MemoryPlatformStore, uid: string, state = 'verified') {
  store.seed('accounts', uid, { uid, state: 'registered', general_access: false, registration_method: 'restricted_seeded_verification', registration_evidence_id: 'evidence_1', registered_at: testTime.toISOString(), authorization_revision: 1 });
  store.seed('psychologist_verifications', uid, { uid, state, revision: 1, changed_at: testTime.toISOString(), changed_by: 'admin_1', audit_id: 'audit_1' });
}
export const manualContent = () => ({ kind: 'custom_questionnaire' as const, validation_status: 'not_validated' as const, origin: 'manual' as const, title: { en: 'Fictional practice form' }, locales: ['en'] as Array<'en'>, questions: [{ id: 'question_1', type: 'short_text' as const, required: true, prompt: { en: 'What would you like to discuss?' }, max_length: 1000 }] });
