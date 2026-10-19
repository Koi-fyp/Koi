import 'server-only';
import { FieldPath, type Firestore } from 'firebase-admin/firestore';
import type { PlatformStore } from './store';
import type { DraftDTO } from '../types';

export function firestoreStore(db: Firestore): PlatformStore {
  return {
    transaction: run => db.runTransaction(async transaction => run({
      get: async <T>(collection: string, id: string) => {
        const snapshot = await transaction.get(db.collection(collection).doc(id));
        return snapshot.exists ? snapshot.data() as T : null;
      },
      create: (collection, id, value) => { transaction.create(db.collection(collection).doc(id), value as FirebaseFirestore.DocumentData); },
      set: (collection, id, value) => { transaction.set(db.collection(collection).doc(id), value as FirebaseFirestore.DocumentData); },
      query: async <T>(collection: string, filters: Record<string, string>, after: string | null, limit: number) => {
        if (!Object.keys(filters).length || limit < 1 || limit > 201) throw new Error('A bounded scope is required');
        let query: FirebaseFirestore.Query = db.collection(collection);
        for (const [field, value] of Object.entries(filters)) query = query.where(field, '==', value);
        query = query.orderBy(FieldPath.documentId()).limit(limit);
        if (after) query = query.startAfter(after);
        return (await transaction.get(query)).docs.map(doc => doc.data() as T);
      },
      drafts: async (organization, owner, after, limit) => {
        let query = db.collection('questionnaires').where('organization_id', '==', organization)
          .where('psychologist_uid', '==', owner).orderBy(FieldPath.documentId()).limit(limit);
        if (after) query = query.startAfter(after);
        const snapshot = await transaction.get(query);
        return snapshot.docs.map(doc => doc.data() as DraftDTO);
      },
    })),
  };
}
