import { db } from '../db';
import type { CBTSession } from '../../models/index';

export class CBTSessionRepository {
  async save(session: CBTSession): Promise<void> {
    await db.cbtSessions.put(session);
  }

  async getById(id: string): Promise<CBTSession | undefined> {
    return db.cbtSessions.get(id);
  }

  async getByUser(userId: string): Promise<CBTSession[]> {
    return db.cbtSessions.where('userId').equals(userId).sortBy('startedAt');
  }

  async getCompletedByUser(userId: string): Promise<CBTSession[]> {
    const all = await this.getByUser(userId);
    return all.filter((s) => s.completedAt !== undefined);
  }

  async getUnsynced(): Promise<CBTSession[]> {
    return db.cbtSessions.where('synced').equals(0).toArray();
  }

  async markSynced(id: string): Promise<void> {
    await db.cbtSessions.update(id, { synced: true });
  }

  async complete(
    id: string,
    opts: { qualityScore?: number; userInsights?: string } = {},
  ): Promise<void> {
    await db.cbtSessions.update(id, {
      completedAt: new Date(),
      ...(opts.qualityScore !== undefined && { quality_score: opts.qualityScore }),
      ...(opts.userInsights !== undefined && { user_insights: opts.userInsights }),
    });
  }

  async delete(id: string): Promise<void> {
    await db.cbtSessions.delete(id);
  }
}

export const cbtSessionRepository = new CBTSessionRepository();
