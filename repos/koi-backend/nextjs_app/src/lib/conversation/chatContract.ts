import type { KoiEmotion } from '../../components/avatar/VRMAvatarController';
export interface ChatTurn { role: 'user' | 'assistant'; content: string; }
export type ExerciseClientEvent = 'playback_done' | 'playback_stopped' | 'start_breathing' | 'start_grounding' | 'start_plan';
export type CrisisPath = 'reached_out' | 'said_but_did_not' | 'misunderstanding';
export interface ChatRequest {
  message: string;
  session_history: ChatTurn[];
  exercise_state?: string | null;
  client_event?: ExerciseClientEvent;
  policy_event?: 'crisis_resolved';
  crisis_path?: CrisisPath;
}
export interface CompanionState { emotion: KoiEmotion; intensity: number; }
export interface ChatResponse { reply: string; companion_state: CompanionState; latency_ms: number; }
export type ChatServerEvent =
  | { event: 'latency'; data: { latency_ms: number } }
  | { event: 'companion_state'; data: CompanionState }
  | { event: 'delta'; data: { text: string } }
  | { event: 'ui_action'; data: { name: string; args: Record<string, unknown> } }
  | { event: 'handoff'; data: { to: 'crisis'; reason: string } }
  | { event: 'state'; data: { exercise_state: string } }
  | { event: 'done'; data: {
      full_text: string;
      companion_state: CompanionState;
      exercise_state?: string | null;
      ui_actions?: Array<{ name: string; args: Record<string, unknown> }>;
      handoff?: { to: 'crisis'; reason: string } | null;
      total_generation_s?: number;
    } };
export interface ChatSendOptions {
  signal: AbortSignal;
  userMessageId: string;
  assistantMessageId: string;
  onEvent?: (event: ChatServerEvent) => void;
}
export interface ChatAdapter { send(request: ChatRequest, options: ChatSendOptions): Promise<ChatResponse>; }
export class ChatError extends Error {
  constructor(public readonly code: 'configuration' | 'authentication' | 'http' | 'invalid-response' | 'timeout' | 'network' | 'redirect' | 'storage', message: string, public readonly status?: number) { super(message); this.name = 'ChatError'; }
}
export function normalizeHistory(history: ReadonlyArray<{ role: string; content: string }>): ChatTurn[] {
  return history.map((turn) => {
    if (!['user', 'assistant', 'model'].includes(turn.role) || typeof turn.content !== 'string') throw new ChatError('invalid-response', 'Invalid conversation history.');
    return { role: turn.role === 'user' ? 'user' : 'assistant', content: turn.content };
  });
}
export function createChatRequest(
  message: string,
  history: ReadonlyArray<{ role: string; content: string }>,
  additions: Pick<ChatRequest, 'exercise_state' | 'client_event' | 'policy_event' | 'crisis_path'> = {},
): ChatRequest {
  if (!message.trim()) throw new ChatError('invalid-response', 'Enter a message first.');
  if (additions.exercise_state !== undefined && additions.exercise_state !== null
    && (typeof additions.exercise_state !== 'string' || additions.exercise_state.length === 0)) {
    throw new ChatError('invalid-response', 'The exercise state is invalid.');
  }
  if (additions.client_event !== undefined && !['playback_done', 'playback_stopped', 'start_breathing', 'start_grounding', 'start_plan'].includes(additions.client_event)) {
    throw new ChatError('invalid-response', 'The activity request is invalid.');
  }
  if ((additions.policy_event === undefined) !== (additions.crisis_path === undefined)
    || (additions.policy_event !== undefined && additions.policy_event !== 'crisis_resolved')
    || (additions.crisis_path !== undefined && !['reached_out', 'said_but_did_not', 'misunderstanding'].includes(additions.crisis_path))) {
    throw new ChatError('invalid-response', 'The safety-flow selection is invalid.');
  }
  return { message: message.trim(), session_history: normalizeHistory(history), ...additions };
}
export function parseChatResponse(raw: unknown): ChatResponse {
  if (!raw || typeof raw !== 'object') throw new ChatError('invalid-response', 'The companion returned an invalid response.');
  const value = raw as Record<string, unknown>;
  if (typeof value.reply !== 'string' || !value.reply.trim() || typeof value.latency_ms !== 'number' || !Number.isFinite(value.latency_ms) || value.latency_ms < 0) throw new ChatError('invalid-response', 'The companion returned an invalid response.');
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
