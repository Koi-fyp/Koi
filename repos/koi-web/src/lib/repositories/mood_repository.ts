import { db } from '../db';
import type { MoodEntry } from '../../models/index';

export class MoodRepository {
  async save(entry: MoodEntry): Promise<void> {
    await db.moodEntries.put(entry);
  }

  async getById(id: string): Promise<MoodEntry | undefined> {
    return db.moodEntries.get(id);
  }

  async getByUser(userId: string): Promise<MoodEntry[]> {
    return db.moodEntries
      .where('userId')
      .equals(userId)
      .sortBy('timestamp');
  }

  async getByUserInRange(userId: string, from: Date, to: Date): Promise<MoodEntry[]> {
    return db.moodEntries
      .where('[userId+timestamp]')
      .between([userId, from], [userId, to], true, true)
      .toArray()
      .catch(() =>
        db.moodEntries
          .where('userId')
          .equals(userId)
          .filter((e) => e.timestamp >= from && e.timestamp <= to)
          .toArray(),
      );
  }

  async getUnsynced(): Promise<MoodEntry[]> {
    return db.moodEntries.where('synced').equals(0).toArray();
  }

  async markSynced(id: string): Promise<void> {
    await db.moodEntries.update(id, { synced: true });
  }

  async delete(id: string): Promise<void> {
    await db.moodEntries.delete(id);
  }
}

export const moodRepository = new MoodRepository();
