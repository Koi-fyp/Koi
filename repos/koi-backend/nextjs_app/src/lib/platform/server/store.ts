import 'server-only';
import type { DraftDTO } from '../types';

export interface PlatformTransaction {
  get<T>(collection: string, id: string): Promise<T | null>;
  create(collection: string, id: string, value: unknown): void;
  set(collection: string, id: string, value: unknown): void;
  query<T>(collection: string, filters: Record<string, string>, after: string | null, limit: number): Promise<T[]>;
  drafts(organization: string, owner: string, after: string | null, limit: number): Promise<DraftDTO[]>;
}
export interface PlatformStore {
  transaction<T>(run: (tx: PlatformTransaction) => Promise<T>): Promise<T>;
}
