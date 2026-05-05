import Dexie, { type Table } from 'dexie';

export interface UserRecord {
  id?: number;
  uid: string;
  avatar?: 'female_human' | 'male_human' | 'fox';
  language?: 'en' | 'ur';
  notificationTime?: string;
  notificationsEnabled?: boolean;
  onboardingComplete?: boolean;
  createdAt?: string;
}

export interface MessageRecord {
  id?: number;
  uid: string;
  role: 'user' | 'assistant';
  content: string;
  timestamp: string;
}

export class KoiDatabase extends Dexie {
  users!: Table<UserRecord, number>;
  messages!: Table<MessageRecord, number>;

  constructor() {
    super('KoiDB');
    this.version(1).stores({
      users: '++id, uid',
      messages: '++id, uid, timestamp',
    });
  }
}

export const db = new KoiDatabase();
