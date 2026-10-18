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
  /** A recorded voice clip sent instead of `message` (the server transcribes it). Never serialized into the JSON payload. */
  audio?: Blob;
}
export interface CompanionState { emotion: KoiEmotion; intensity: number; }
export type RiskCategory = 'LOW' | 'MODERATE' | 'HIGH' | 'CRITICAL';
export interface BackendInterventionContent {
  source: 'grounded' | 'fallback'; language: string;
  items: Array<{ text: string; chunk_id: string; source_corpus: string; evidence_role: string; review_status: string }>;
  helpline?: { name: string; number: string; verified: boolean };
}
export type RiskResult = { status: 'unavailable' } | {
  status: 'ok'; risk_category: RiskCategory; crisis_score: number;
  confidence: 'standard' | 'reduced'; confidence_reasons: string[];
  modalities_used: Array<'text' | 'audio' | 'video'>; trigger_flags: string[];
  intervention_content?: BackendInterventionContent; model: { version: string; calibrated: boolean };
};
export type ChatErrorCode = 'no_reply' | 'generation_failed';
export interface TranscriptEvent { text: string; language?: string; }
export interface ChatResponse { reply: string; companion_state: CompanionState; latency_ms: number; }
export type ChatServerEvent =
  | { event: 'transcript'; data: TranscriptEvent }
  | { event: 'risk'; data: RiskResult }
  | { event: 'error'; data: { code: ChatErrorCode } }
  | { event: 'latency'; data: { latency_ms: number } }
  | { event: 'companion_state'; data: CompanionState }
  | { event: 'delta'; data: { text: string } }
  | { event: 'ui_action'; data: { name: string; args: Record<string, unknown> } }
  | { event: 'handoff'; data: { to: 'crisis'; reason: string } }
  | { event: 'state'; data: { exercise_state: string | null } }
  | { event: 'done'; data: {
      full_text: string;
      companion_state: CompanionState;
      exercise_state?: string | null;
      ui_actions?: Array<{ name: string; args: Record<string, unknown> }>;
      handoff?: { to: 'crisis'; reason: string } | null;
      total_generation_s?: number;
      risk?: RiskResult;
    } };
export interface ChatSendOptions {
  signal: AbortSignal;
  userMessageId: string;
  assistantMessageId: string;
  onEvent?: (event: ChatServerEvent) => void;
}
export interface ChatAdapter { send(request: ChatRequest, options: ChatSendOptions): Promise<ChatResponse>; }
export class ChatError extends Error {
  constructor(public readonly code: 'configuration' | 'authentication' | 'http' | 'invalid-response' | 'timeout' | 'network' | 'redirect' | 'storage' | 'generation', message: string, public readonly status?: number) { super(message); this.name = 'ChatError'; }
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
  { voice = false }: { voice?: boolean } = {},
): ChatRequest {
  // The server accepts text or audio, never both: a voice turn carries an empty message.
  if (voice ? message.trim() : !message.trim()) throw new ChatError('invalid-response', voice ? 'Send either text or a voice message.' : 'Enter a message first.');
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

const boundedString = (value: unknown, max = 500): value is string => typeof value === 'string' && value.length <= max;
function parseInterventionContent(raw: unknown): BackendInterventionContent | undefined {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return undefined;
  const value = raw as Record<string, unknown>;
  if ((value.source !== 'grounded' && value.source !== 'fallback') || !boundedString(value.language, 24)
    || !Array.isArray(value.items) || value.items.length < 1 || value.items.length > 3) return undefined;
  const items: BackendInterventionContent['items'] = [];
  for (const rawItem of value.items) {
    if (!rawItem || typeof rawItem !== 'object' || Array.isArray(rawItem)) return undefined;
    const item = rawItem as Record<string, unknown>;
    if (!boundedString(item.text, 1200) || !item.text.trim() || !boundedString(item.chunk_id, 120)
      || !item.chunk_id.trim() || !boundedString(item.source_corpus, 160) || !boundedString(item.evidence_role, 80)
      || !boundedString(item.review_status, 80)) return undefined;
    items.push({ text: item.text, chunk_id: item.chunk_id, source_corpus: item.source_corpus,
      evidence_role: item.evidence_role, review_status: item.review_status });
  }
  let helpline: BackendInterventionContent['helpline'];
  if (value.helpline !== undefined) {
    if (!value.helpline || typeof value.helpline !== 'object' || Array.isArray(value.helpline)) return undefined;
    const candidate = value.helpline as Record<string, unknown>;
    if (!boundedString(candidate.name, 100) || !candidate.name.trim() || !boundedString(candidate.number, 40)
      || !candidate.number.trim() || typeof candidate.verified !== 'boolean') return undefined;
    helpline = { name: candidate.name, number: candidate.number, verified: candidate.verified };
  }
  return { source: value.source, language: value.language, items, ...(helpline ? { helpline } : {}) };
}

export function parseRiskResult(raw: unknown): RiskResult | null {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const value = raw as Record<string, unknown>;
  if (value.status === 'unavailable') return { status: 'unavailable' };
  const categories = ['LOW', 'MODERATE', 'HIGH', 'CRITICAL'];
  if (value.status !== 'ok' || typeof value.risk_category !== 'string' || !categories.includes(value.risk_category)) return null;
  const scoreValid = typeof value.crisis_score === 'number' && Number.isFinite(value.crisis_score) && value.crisis_score >= 0 && value.crisis_score <= 1;
  const confidence = value.confidence === 'standard' || value.confidence === 'reduced' ? value.confidence : undefined;
  const reasonsValid = Array.isArray(value.confidence_reasons) && value.confidence_reasons.every((item) => boundedString(item, 120));
  const modalities = ['text', 'audio', 'video'];
  const modalitiesValid = Array.isArray(value.modalities_used) && value.modalities_used.every((item) => typeof item === 'string' && modalities.includes(item));
  const flagsValid = Array.isArray(value.trigger_flags) && value.trigger_flags.every((item) => boundedString(item, 120));
  if (!scoreValid || !confidence || !reasonsValid || !modalitiesValid || !flagsValid
    || !value.model || typeof value.model !== 'object' || Array.isArray(value.model)) return null;
  const modelCandidate = value.model as Record<string, unknown>;
  if (!boundedString(modelCandidate.version, 120) || !modelCandidate.version.trim() || typeof modelCandidate.calibrated !== 'boolean') return null;
  const intervention_content = value.intervention_content === undefined ? undefined : parseInterventionContent(value.intervention_content);
  return { status: 'ok', risk_category: value.risk_category as RiskCategory,
    crisis_score: value.crisis_score as number, confidence,
    confidence_reasons: value.confidence_reasons as string[],
    modalities_used: value.modalities_used as Array<'text' | 'audio' | 'video'>,
    trigger_flags: value.trigger_flags as string[],
    ...(intervention_content ? { intervention_content } : {}),
    model: { version: modelCandidate.version, calibrated: modelCandidate.calibrated } };
}
export function chatErrorMessage(error: unknown): string {
  if (error instanceof ChatError) return error.message;
  return 'The message could not be completed. Please try again.';
}
