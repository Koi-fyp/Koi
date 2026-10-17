import type { User } from 'firebase/auth';
import { auth } from '../firebase';
import { db, type MessageRecord, type Emotion as StoredEmotion } from '../db';
import { syncQueue } from '../firestore/sync';
import { encrypt, getActiveCryptoContext, type AuthState } from '../crypto';
import { ChatError, type ChatTurn, type ChatResponse, type ChatSendOptions, type ChatRequest } from './chatContract';
import { singleFlight } from './singleFlight';
import { chatEndpoint, postJsonChat } from './jsonChatTransport';
export type { ChatTurn } from './chatContract';
export type Emotion = import('../../components/avatar/VRMAvatarController').KoiEmotion;
export type SendMessageResult = ChatResponse;
// Prevent concurrent first-use anonymous lookups from generating competing salts.
// Linked accounts continue using the existing strict salt/secret policy directly.
const anonymousCryptoContext = singleFlight((uid: string) => getActiveCryptoContext(uid, { isLinked: false }));
function storedEmotion(emotion: Emotion): StoredEmotion {
  return emotion === 'joy' ? 'happy' : emotion === 'sorrow' ? 'sad' : emotion === 'fun' ? 'calm' : 'neutral';
}
/** Existing encrypted persistence format/queue retained; only optional companion metadata is additive. */
async function saveMessage(record: MessageRecord, secret: string, saltB64: string, signal: AbortSignal) {
  signal.throwIfAborted();
  const encrypted = { ...record, content: await encrypt(record.content, secret, saltB64) };
  signal.throwIfAborted();
  await db.messages.put(encrypted);
  // Once a local write commits, queue the same ciphertext for consistency even if cancellation races it.
  syncQueue.enqueue({ collection: `conversations/${record.conversationId}/messages`, docId: record.id,
    data: encrypted as unknown as Record<string, unknown>, priority: 3 });
}
export async function sendMessage(uid: string, conversationId: string, text: string, context: ChatTurn[], authState: AuthState, options: ChatSendOptions,
  requestFields: Pick<ChatRequest, 'exercise_state' | 'client_event' | 'policy_event' | 'crisis_path'> = {}): Promise<ChatResponse> {
  options.signal.throwIfAborted();
  const user = auth?.currentUser as User | undefined;
  if (!user || user.uid !== uid) throw new ChatError('authentication', 'An authenticated KOI session is required.');
  const linked = !user.isAnonymous && user.providerData.some((provider) => provider.providerId === 'password');
  if (linked !== authState.isLinked) throw new ChatError('authentication', 'Your account state changed. Start a new chat session.');
  if (linked && !authState.linkedSecret) throw new ChatError('storage', 'Unlock your linked account before chatting.');
  chatEndpoint(process.env.NEXT_PUBLIC_KOI_API_BASE); // No accidental same-origin request or external fallback.
  const token = await user.getIdToken();
  if (!token) throw new ChatError('authentication', 'An authenticated KOI session is required.');
  options.signal.throwIfAborted();
  const ensureOwner = () => { const active = auth?.currentUser as User | undefined; const activeLinked = active && !active.isAnonymous && active.providerData.some((provider) => provider.providerId === 'password'); if (active?.uid !== uid || !!activeLinked !== linked) throw new ChatError('authentication', 'Your account changed. Start a new chat session.'); };
  ensureOwner();
  const { secret, saltB64 } = await (linked ? getActiveCryptoContext(uid, authState) : anonymousCryptoContext(uid));
  ensureOwner(); options.signal.throwIfAborted();
  await saveMessage({ id: options.userMessageId, conversationId, sender: 'user', content: text, timestamp: new Date(), emotion: 'neutral', synced: false }, secret, saltB64, options.signal);
  options.signal.throwIfAborted(); ensureOwner();
  const response = await postJsonChat({ message: text, session_history: context, ...requestFields }, {
    apiBase: process.env.NEXT_PUBLIC_KOI_API_BASE, headers: new Headers({ Authorization: `Bearer ${token}` }), signal: options.signal,
    onEvent: (event) => {
      options.signal.throwIfAborted();
      ensureOwner();
      options.onEvent?.(event);
    },
  });
  options.signal.throwIfAborted(); ensureOwner();
  await saveMessage({ id: options.assistantMessageId, conversationId, sender: 'ai', content: response.reply,
    timestamp: new Date(), emotion: storedEmotion(response.companion_state.emotion), companion_state: response.companion_state, synced: false }, secret, saltB64, options.signal);
  return response;
}
