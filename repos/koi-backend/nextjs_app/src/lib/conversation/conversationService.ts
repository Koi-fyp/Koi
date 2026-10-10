// KOI — conversationService.ts, rewired to the self-hosted /api/v1/chat endpoint.
//
// Replaces the quarantined Firebase Cloud Function -> geminiClient.ts -> Gemini
// external API path (the committee-rejected architecture) with a direct call to
// the self-hosted FastAPI/vLLM endpoint.
//
// Contract decision and full reasoning: SESSION_HANDOFF.md §17.
// Nested schema per Blueprint §4.1. SSE transport per §4.1e.
//
// WHAT CHANGED, and what deliberately did NOT:
//   - httpsCallable(...) -> fetch() with an Authorization: Bearer <Firebase ID token>.
//     The backend verifies via firebase-admin and derives identity STRICTLY from the
//     token's `sub` claim (Blueprint §4.1 SECURITY RULE). userId is still passed for
//     local persistence/crypto only -- it is NOT the backend's identity source.
//   - Awaiting one atomic JSON object -> consuming an SSE stream (latency, delta, done).
//     Blueprint §4.1e: "a real contract evolution both client tracks need to account for."
//   - `emotion` now arrives nested under companion_state.
//   - crisis_flag / sentiment_score REMOVED from this path. They belong to the TSD
//     Crisis Engine's /api/v1/crisis schema, not the chat reply (SESSION_HANDOFF.md §17.4).
//     They are NOT defaulted to false/0 on the record -- Blueprint §4.1 treats a `false`
//     default in a crisis context as indistinguishable from "checked and found clear,"
//     which is a false-negative risk. They are left undefined until TSD supplies them.
//   - UNCHANGED, deliberately: saveMessage(), the encrypt/syncQueue path, the
//     user-message-saved-before-AI-reply ordering, and the catch-block fallback reply.
//     None of that depends on which backend is called.
//
// STILL OPEN (do not treat as settled):
//   - `Emotion` below is the pre-existing deployed union. The backend currently emits an
//     UNCONSTRAINED string for emotion (its 32-class taxonomy is still unenumerated in
//     canon -- Blueprint §4.1 v4.23 note). normalizeEmotion() below is a deliberate,
//     visible shim, not a canonical mapping. Replace it once the taxonomy is locked.
//   - NEXT_PUBLIC_KOI_API_BASE must point at the deployed endpoint. The Modal `modal serve`
//     URL is EPHEMERAL and changes per session -- use a `modal deploy` URL for anything
//     persistent.

import { getAuth } from 'firebase/auth';
import { db, MessageRecord } from '../db';
import { syncQueue } from '../firestore/sync';
import { v4 as uuidv4 } from 'uuid';
import { encrypt, getActiveCryptoContext } from '../crypto';

const API_BASE = process.env.NEXT_PUBLIC_KOI_API_BASE ?? '';

export type Emotion = 'happy' | 'sad' | 'anxious' | 'calm' | 'neutral';

/** Backend's nested shape (Blueprint §4.1). Note: no crisis_flag, no sentiment_score. */
export interface SendMessageResult {
  reply: string;
  emotion: Emotion;
  /** TTFT in ms, server-measured. Blueprint §4.1 latency contract. */
  latencyMs: number | null;
}

export interface ChatTurn {
  role: 'user' | 'model';
  content: string;
}

/**
 * Deliberate, visible shim -- NOT a canonical mapping.
 * The backend emits an unconstrained emotion string; this collapses it onto the
 * deployed union so the avatar has something valid to render. Unrecognized values
 * fall back to 'neutral' rather than throwing, so an unexpected label degrades the
 * expression instead of breaking the chat. Remove once the taxonomy is locked.
 */
function normalizeEmotion(raw: unknown): Emotion {
  const known: Emotion[] = ['happy', 'sad', 'anxious', 'calm', 'neutral'];
  if (typeof raw === 'string' && (known as string[]).includes(raw)) {
    return raw as Emotion;
  }
  if (typeof raw === 'string') {
    console.warn('[KOI] Unmapped emotion from backend, using neutral:', raw);
  }
  return 'neutral';
}

async function saveMessage(record: MessageRecord, uid: string): Promise<void> {
  const { secret, saltB64 } = await getActiveCryptoContext(uid);
  const encryptedRecord: MessageRecord = {
    ...record,
    content: await encrypt(record.content, secret, saltB64),
  };

  await db.messages.put(encryptedRecord);
  syncQueue.enqueue({
    collection: `conversations/${record.conversationId}/messages`,
    docId: record.id,
    data: encryptedRecord as unknown as Record<string, unknown>,
    priority: 3,
  });
}

/**
 * Consumes the endpoint's SSE stream.
 * Events, in order: `latency` (server TTFT + emotion context), `delta` (text chunks),
 * `done` (full text). onDelta fires per chunk so the UI can stream if it chooses to;
 * callers that don't pass it simply get the assembled reply, preserving the existing
 * non-streaming call shape.
 */
async function streamChat(
  idToken: string,
  message: string,
  sessionHistory: ChatTurn[],
  onDelta?: (chunk: string) => void,
): Promise<{ fullText: string; emotion: Emotion; latencyMs: number | null }> {
  const res = await fetch(`${API_BASE}/api/v1/chat`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${idToken}`,
    },
    body: JSON.stringify({ message, session_history: sessionHistory }),
  });

  // Check status BEFORE parsing -- an auth failure returns a normal JSON error body,
  // not an SSE stream, and silently parsing it as SSE yields a confusing empty result.
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`/api/v1/chat returned ${res.status}: ${body.slice(0, 300)}`);
  }
  if (!res.body) throw new Error('/api/v1/chat returned no response body');

  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  let fullText = '';
  let emotion: Emotion = 'neutral';
  let latencyMs: number | null = null;
  let currentEvent: string | null = null;

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });

    // SSE frames are separated by a blank line; keep the trailing partial in the buffer.
    const frames = buffer.split('\n\n');
    buffer = frames.pop() ?? '';

    for (const frame of frames) {
      for (const line of frame.split('\n')) {
        if (line.startsWith('event: ')) {
          currentEvent = line.slice(7).trim();
        } else if (line.startsWith('data: ')) {
          let payload: Record<string, unknown>;
          try {
            payload = JSON.parse(line.slice(6));
          } catch {
            console.warn('[KOI] Unparseable SSE data line, skipping');
            continue;
          }
          if (currentEvent === 'latency') {
            latencyMs = typeof payload.latency_ms === 'number' ? payload.latency_ms : null;
          } else if (currentEvent === 'delta') {
            const chunk = typeof payload.text === 'string' ? payload.text : '';
            if (chunk) {
              fullText += chunk;
              onDelta?.(chunk);
            }
          } else if (currentEvent === 'done') {
            if (typeof payload.full_text === 'string' && payload.full_text) {
              fullText = payload.full_text;
            }
            const state = payload.companion_state as Record<string, unknown> | undefined;
            if (state) emotion = normalizeEmotion(state.emotion);
          }
        }
      }
    }
  }

  return { fullText, emotion, latencyMs };
}

export async function sendMessage(
  userId: string,
  conversationId: string,
  text: string,
  context: ChatTurn[],
  _userProfile: unknown,  // retained for call-site compatibility; not sent to /api/v1/chat
  onDelta?: (chunk: string) => void,
): Promise<SendMessageResult> {
  const userMsgId = uuidv4();

  // UNCHANGED: user message persisted before the AI call, exactly as before.
  await saveMessage({
    id: userMsgId,
    conversationId,
    sender: 'user',
    content: text,
    timestamp: new Date(),
    emotion: 'neutral',
    emotion_confidence: 1,
    synced: false,
  } as MessageRecord, userId);

  try {
    const user = getAuth().currentUser;
    if (!user) throw new Error('No authenticated Firebase user -- cannot call /api/v1/chat');
    const idToken = await user.getIdToken();

    const { fullText, emotion, latencyMs } = await streamChat(idToken, text, context, onDelta);

    await saveMessage({
      id: uuidv4(),
      conversationId,
      sender: 'ai',
      content: fullText,
      timestamp: new Date(),
      emotion,
      emotion_confidence: 1,
      synced: false,
    } as MessageRecord, userId);

    return { reply: fullText, emotion, latencyMs };
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
      synced: false,
    } as MessageRecord, userId);

    return { reply: fallbackReply, emotion: 'calm', latencyMs: null };
  }
}
