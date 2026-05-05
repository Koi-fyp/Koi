import { db } from '../db';
import type { User } from '../../models/index';

export class UserRepository {
  async save(user: User): Promise<void> {
    await db.users.put(user);
  }

  async getById(id: string): Promise<User | undefined> {
    return db.users.get(id);
  }

  async updateLastActive(id: string): Promise<void> {
    await db.users.update(id, { lastActive: new Date() });
  }

  async delete(id: string): Promise<void> {
    await db.users.delete(id);
  }

  async getAll(): Promise<User[]> {
    return db.users.toArray();
  }
}

export const userRepository = new UserRepository();
