import { getFunctions, httpsCallable, connectFunctionsEmulator } from 'firebase/functions';
import { getApp } from 'firebase/app';
import { db, MessageRecord } from '../db';
import { syncQueue } from '../firestore/sync';
import { v4 as uuidv4 } from 'uuid';

// Instantiate once at module level so connectFunctionsEmulator is only called once
const functions = getFunctions(getApp());
if (process.env.NODE_ENV === 'development') {
  connectFunctionsEmulator(functions, '127.0.0.1', 5001);
}

export type Emotion = 'happy' | 'sad' | 'anxious' | 'calm' | 'neutral';

export interface SendMessageResult {
  reply: string;
  emotion: Emotion;
  crisis_flag: boolean;
  sentiment_score: number;
}

interface FirebaseCallPayload {
  message: string;
  conversationId: string;
  context: unknown[];
  userId: string;
  userProfile: unknown;
}

async function saveMessage(record: MessageRecord): Promise<void> {
  await db.messages.put(record);
  syncQueue.enqueue({
    collection: `conversations/${record.conversationId}/messages`,
    docId: record.id,
    data: record as unknown as Record<string, unknown>,
    priority: 3,
  });
}

export async function sendMessage(
  userId: string,
  conversationId: string,
  text: string,
  context: unknown[],
  userProfile: unknown,
): Promise<SendMessageResult> {
  const userMsgId = uuidv4();

  await saveMessage({
    id: userMsgId,
    conversationId,
    sender: 'user',
    content: text,
    timestamp: new Date(),
    emotion: 'neutral',
    emotion_confidence: 1,
    sentiment_score: 0,
    crisis_flag: false,
    synced: false,
  });

  try {
    const callable = httpsCallable<FirebaseCallPayload, SendMessageResult>(
      functions,
      'sendMessage',
    );
    const result = await callable({ message: text, conversationId, context, userId, userProfile });

    await saveMessage({
      id: uuidv4(),
      conversationId,
      sender: 'ai',
      content: result.data.reply,
      timestamp: new Date(),
      emotion: result.data.emotion,
      emotion_confidence: 1,
      sentiment_score: result.data.sentiment_score,
      crisis_flag: result.data.crisis_flag,
      synced: false,
    });

    return result.data;
  } catch (err) {
    console.error('[KOI] sendMessage failed:', err);
    const fallbackReply = "I'm having a little trouble connecting right now. I'm still here with you.";

    await saveMessage({
      id: uuidv4(),
      conversationId,
      sender: 'ai',
      content: fallbackReply,
      timestamp: new Date(),
      emotion: 'calm',
      emotion_confidence: 1,
      sentiment_score: 0,
      crisis_flag: false,
      synced: false,
    });

    return {
      reply: fallbackReply,
      emotion: 'calm',
      crisis_flag: false,
      sentiment_score: 0,
    };
  }
}
