"use client";
import Dexie, { type Table } from 'dexie';
export type Emotion = 'happy' | 'sad' | 'anxious' | 'calm' | 'neutral';
export interface ConversationMessageRecord {
  id: string;
  conversationId: string;
  sender: 'user' | 'ai';
  content: string;
  timestamp: Date;
  emotion: Emotion;
  emotion_confidence?: number;
  sentiment_score?: number;
  crisis_flag?: boolean;
  /** Optional additive presentation metadata; legacy records require no rewrite/index migration. */
  companion_state?: import('./conversation/chatContract').CompanionState;
  synced: boolean;
  ownerUid?: string;
  replyTo?: string;
}
export interface UserRecord {
  id?: number;
  uid: string;
  /** `fox` is a persisted onboarding choice from the legacy model picker; retain it until an explicit migration. */
  avatar?: 'female_human' | 'male_human' | 'fox';
  companion?: 'aisha' | 'raza' | 'koi';
  language?: 'en' | 'ur';
  notificationTime?: string;
  notificationsEnabled?: boolean;
  onboardingComplete?: boolean;
  createdAt?: string;
}
export interface JigsawProgressRecord {
  uid: string;
  jigsaw_pieces: number;
  pieces_by_source: {
    conversations: number;
    check_ins: number;
    breathing: number;
    tasks: number;
    bonuses: number;
  };
  milestones_reached: number[];
  last_updated: Date;
}
export interface MoodEntryRecord {
  id: string;
  userId: string;
  timestamp: Date;
  mood_rating: number;
  connection_rating: number;
  energy_rating: number;
  loneliness_score: number;
  synced: boolean;
}
export interface MessageRecord extends ConversationMessageRecord {}
export interface SyncQueueRecord {
  id?: number;
  collection: string;
  docId: string;
  data: Record<string, unknown>;
  priority: number;
  createdAt: Date;
}
export interface ConversationRecord {
  uid: string;
  conversationId: string;
  createdAt: Date;
  lastActiveAt: Date;
  status: 'active';
  revision: number;
  /** Entire session snapshot is CSE ciphertext; no plaintext transcript or safety state. */
  encryptedState?: string;
}
export class KoiDatabase extends Dexie {
  conversations!: Table<ConversationRecord, string>;
  users!: Table<UserRecord, number>;
  messages!: Table<MessageRecord, string>;
  moodEntries!: Table<MoodEntryRecord, string>;
  jigsawProgress!: Table<JigsawProgressRecord, string>;
  syncQueue!: Table<SyncQueueRecord, number>;
  constructor() {
    super('KoiDB');
    this.version(1).stores({
      users: '++id, uid',
      messages: 'id, conversationId, synced, timestamp',
      moodEntries: 'id, userId, synced, timestamp',
      jigsawProgress: 'uid',
      syncQueue: '++id, priority, createdAt',
    });
    this.version(2).stores({ conversations: 'uid, conversationId, lastActiveAt' });
  }
}
export const db = new KoiDatabase();
