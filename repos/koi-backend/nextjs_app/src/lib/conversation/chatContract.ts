import type { KoiEmotion } from '../../components/avatar/VRMAvatarController';
export interface ChatTurn { role: 'user' | 'assistant'; content: string; }
export interface ChatRequest { message: string; session_history: ChatTurn[]; }
export interface CompanionState { emotion: KoiEmotion; intensity: number; }
export interface ChatResponse { reply: string; companion_state: CompanionState; latency_ms: number; }
export interface ChatSendOptions { signal: AbortSignal; userMessageId: string; assistantMessageId: string; }
export interface ChatAdapter { send(request: ChatRequest, options: ChatSendOptions): Promise<ChatResponse>; }
export class ChatError extends Error {
  constructor(public readonly code: 'configuration' | 'authentication' | 'http' | 'invalid-response' | 'timeout' | 'network' | 'storage', message: string, public readonly status?: number) { super(message); this.name = 'ChatError'; }
}
export function normalizeHistory(history: ReadonlyArray<{ role: string; content: string }>): ChatTurn[] {
  return history.map((turn) => {
    if (!['user', 'assistant', 'model'].includes(turn.role) || typeof turn.content !== 'string') throw new ChatError('invalid-response', 'Invalid conversation history.');
    return { role: turn.role === 'user' ? 'user' : 'assistant', content: turn.content };
  });
}
export function createChatRequest(message: string, history: ReadonlyArray<{ role: string; content: string }>): ChatRequest {
  if (!message.trim()) throw new ChatError('invalid-response', 'Enter a message first.');
  return { message: message.trim(), session_history: normalizeHistory(history) };
}
export function parseChatResponse(raw: unknown): ChatResponse {
  if (!raw || typeof raw !== 'object') throw new ChatError('invalid-response', 'The companion returned an invalid response.');
  const value = raw as Record<string, unknown>;
  if (typeof value.reply !== 'string' || !value.reply.trim() || typeof value.latency_ms !== 'number' || !Number.isFinite(value.latency_ms) || !Number.isInteger(value.latency_ms) || value.latency_ms < 0) throw new ChatError('invalid-response', 'The companion returned an invalid response.');
  const state = value.companion_state && typeof value.companion_state === 'object' ? value.companion_state as Record<string, unknown> : {};
  const known = typeof state.emotion === 'string' && ['neutral', 'joy', 'angry', 'sorrow', 'fun'].includes(state.emotion);
  const emotion = known ? state.emotion as KoiEmotion : 'neutral';
  return { reply: value.reply, latency_ms: value.latency_ms, companion_state: {
    emotion, intensity: known && typeof state.intensity === 'number' && Number.isFinite(state.intensity) ? Math.min(1, Math.max(0, state.intensity)) : 0,
  } };
}
export function chatErrorMessage(error: unknown): string {
  if (error instanceof ChatError) return error.message;
  return 'The message could not be completed. Please try again.';
}
