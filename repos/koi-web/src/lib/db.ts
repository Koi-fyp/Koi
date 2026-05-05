import Dexie, { type Table } from 'dexie';
import type { User, Message, MoodEntry, CBTSession, Task } from '../models/index';

class KoiDatabase extends Dexie {
  users!: Table<User>;
  messages!: Table<Message>;
  moodEntries!: Table<MoodEntry>;
  cbtSessions!: Table<CBTSession>;
  tasks!: Table<Task>;

  constructor() {
    super('KoiDB');

    this.version(1).stores({
      users: 'id, createdAt',
      messages: 'id, conversationId, timestamp, synced',
      moodEntries: 'id, userId, timestamp, synced',
      cbtSessions: 'id, userId, startedAt, synced',
      tasks: 'id, userId, createdAt, synced, archived',
    });
  }
}

export const db = new KoiDatabase();
export type { KoiDatabase };
