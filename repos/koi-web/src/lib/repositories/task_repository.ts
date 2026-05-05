import { db } from '../db';
import type { Task } from '../../models/index';

export class TaskRepository {
  async save(task: Task): Promise<void> {
    await db.tasks.put(task);
  }

  async getById(id: string): Promise<Task | undefined> {
    return db.tasks.get(id);
  }

  async getActiveByUser(userId: string): Promise<Task[]> {
    return db.tasks
      .where('userId')
      .equals(userId)
      .filter((t) => !t.archived)
      .toArray();
  }

  async getCompletedByUser(userId: string): Promise<Task[]> {
    return db.tasks
      .where('userId')
      .equals(userId)
      .filter((t) => t.completedAt !== undefined)
      .toArray();
  }

  async getUnsynced(): Promise<Task[]> {
    return db.tasks.where('synced').equals(0).toArray();
  }

  async markSynced(id: string): Promise<void> {
    await db.tasks.update(id, { synced: true });
  }

  async complete(id: string): Promise<void> {
    await db.tasks.update(id, { completedAt: new Date() });
  }

  async archive(id: string): Promise<void> {
    await db.tasks.update(id, { archived: true });
  }

  async delete(id: string): Promise<void> {
    await db.tasks.delete(id);
  }
}

export const taskRepository = new TaskRepository();
