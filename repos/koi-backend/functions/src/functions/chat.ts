import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { GeminiClient } from '../lib/geminiClient';
import type { SendMessageInput, SendMessageOutput } from '../types/index';

const geminiClient = new GeminiClient(process.env.GEMINI_API_KEY ?? '');

function validateInput(data: unknown): SendMessageInput {
  if (!data || typeof data !== 'object') {
    throw new HttpsError('invalid-argument', 'Request data must be an object');
  }
  const d = data as Record<string, unknown>;

  if (typeof d.message !== 'string' || d.message.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'message must be a non-empty string');
  }
  if (typeof d.conversationId !== 'string' || !d.conversationId) {
    throw new HttpsError('invalid-argument', 'conversationId is required');
  }
  if (typeof d.userId !== 'string' || !d.userId) {
    throw new HttpsError('invalid-argument', 'userId is required');
  }
  if (!Array.isArray(d.context)) {
    throw new HttpsError('invalid-argument', 'context must be an array');
  }
  if (!d.userProfile || typeof d.userProfile !== 'object') {
    throw new HttpsError('invalid-argument', 'userProfile is required');
  }

  return d as unknown as SendMessageInput;
}

export const sendMessage = onCall(
  {
    enforceAppCheck: false,
    timeoutSeconds: 30,
    memory: '256MiB',
  },
  async (request): Promise<SendMessageOutput> => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Request must be authenticated');
    }

    const input = validateInput(request.data);

    // Trust userId from input but double-check it matches auth token
    if (request.auth.uid !== input.userId) {
      throw new HttpsError('permission-denied', 'userId does not match authenticated user');
    }

    const geminiResult = await geminiClient.sendMessage(
      input.message.trim(),
      input.context.slice(-5),
      input.userProfile,
      input.userId,
    );

    return {
      ...geminiResult,
      conversationId: input.conversationId,
    };
  },
);
