// KOI — conversationService.ts, contract v1 reference client (docs/contracts/KOI_CLIENT_CONTRACT_v1.md).
//
// Status: PROPOSED reference for the Web team, chat-generated Oct 16 2026. Type-checked only; never run against a
// live deployment. Replaces the Oct 15 SSE draft (which never shipped) and, per canon, the quarantined
// Firebase Cloud Function -> Gemini path.
//
// What this adds over the Oct 15 draft:
//   - emotion = the 5 canon strings (neutral | joy | angry | sorrow | fun), read from the `companion_state` event
//   - session roles 'user' | 'assistant' (the server still accepts 'model' for old callers)
//   - exercise director plumbing: exercise_state echo, client_event, ui_action / handoff / state events
//   - TSD: /api/v1/crisis fired in parallel every turn, never awaited before the reply; its latest result is sent
//     as `risk` on the next chat request (is_new once); UX Flow 4 resolution via policy_event / crisis_path
//
// UNCHANGED from the draft, deliberately: saveMessage() (encrypt + syncQueue), user message saved before the AI
// call, and the catch-block fallback reply.

import { getAuth } from 'firebase/auth';
import { db, MessageRecord } from '../db';
import { syncQueue } from '../firestore/sync';
import { v4 as uuidv4 } from 'uuid';
import { encrypt, getActiveCryptoContext } from '../crypto';

const CHAT_BASE = process.env.NEXT_PUBLIC_KOI_API_BASE ?? '';
const CRISIS_BASE = process.env.NEXT_PUBLIC_KOI_CRISIS_BASE ?? '';
const CRISIS_TIMEOUT_MS = 20_000;

// ---------------------------------------------------------------- contract types
export type Emotion = 'neutral' | 'joy' | 'angry' | 'sorrow' | 'fun';
const EMOTIONS: readonly Emotion[] = ['neutral', 'joy', 'angry', 'sorrow', 'fun'];

export interface CompanionState { emotion: Emotion; intensity: number; }
export interface ChatTurn { role: 'user' | 'assistant'; content: string; }
export type ClientEvent =
  | 'none' | 'playback_done' | 'playback_stopped' | 'start_breathing' | 'start_grounding' | 'start_plan';
export type RiskCategory = 'LOW' | 'MODERATE' | 'HIGH' | 'CRITICAL';
export type CrisisPath = 'reached_out' | 'said_but_did_not' | 'misunderstanding';
export interface UiAction { name: string; args: Record<string, unknown>; }
export interface Handoff { to: 'crisis'; reason: string; }

export interface InterventionContent {
  source: 'grounded' | 'fallback';
  language: string;
  items: { text: string; chunk_id: string; source_corpus: string; evidence_role: string; review_status: string }[];
  helpline?: { name: string; number: string; verified?: boolean };
}
export interface CrisisResult {
  crisis_score: number;
  risk_category: RiskCategory;
  modalities_used: string[];
  trigger_flags: string[];
  confidence: 'standard' | 'reduced';
  confidence_reasons: string[];
  intervention_content?: InterventionContent;
  turn_id?: string;
  [extra: string]: unknown; // contract: ignore unknown fields
}

export interface ChatHandlers {
  onCompanionState?: (s: CompanionState) => void; // fires before any text: drive the avatar
  onDelta?: (text: string) => void;               // reply text only; exercise turns = one sentence per call
  onUiAction?: (a: UiAction, urgent: boolean) => void;
  onHandoff?: (h: Handoff) => void;
}
export interface ChatResult {
  fullText: string;
  companionState: CompanionState;
  exerciseState: string | null;
  uiActions: UiAction[];
  handoff: Handoff | null;
  latencyMs: number | null;
}

function toEmotion(raw: unknown): Emotion {
  return typeof raw === 'string' && (EMOTIONS as readonly string[]).includes(raw) ? (raw as Emotion) : 'neutral';
}
function toCompanionState(raw: unknown): CompanionState {
  const o = (raw ?? {}) as Record<string, unknown>;
  const x = typeof o.intensity === 'number' ? Math.min(Math.max(o.intensity, 0), 1) : 0.4;
  return { emotion: toEmotion(o.emotion), intensity: x };
}

// ---------------------------------------------------------------- per-conversation state
/** Keep one per conversation (persist it with the conversation if the app can be closed mid-exercise). */
export class KoiConversationState {
  exerciseState: string | null = null;
  pendingClientEvent: ClientEvent = 'none';
  latestRisk: CrisisResult | null = null;
  latestRiskSent = false;
  crisisFlowOpen = false;
  pendingCrisisResolution: CrisisPath | null = null;
  turnSeq = 0;              // incremented per user turn
  private latestRiskSeq = -1;
  private minRiskSeq = 0;   // results from turns before a crisis resolution are ignored

  /** Call when the breathing animation finishes (or the user stops it). Sent with the next chat request. */
  markPlayback(done: boolean): void { this.pendingClientEvent = done ? 'playback_done' : 'playback_stopped'; }
  /** Call from an exercise button. */
  startExercise(kind: 'start_breathing' | 'start_grounding' | 'start_plan'): void { this.pendingClientEvent = kind; }
  /** Call when the user finishes UX Flow 4. Drops the held risk so an old HIGH does not re-enter crisis. */
  resolveCrisis(path: CrisisPath): void {
    this.pendingCrisisResolution = path;
    this.crisisFlowOpen = false;
    this.latestRisk = null;
    this.latestRiskSent = true;
    this.minRiskSeq = this.turnSeq + 1;
  }
  /** Store a crisis result only if it is newer than the one held (results can arrive out of order). */
  acceptRisk(r: CrisisResult, seq: number): boolean {
    if (seq < this.minRiskSeq || seq <= this.latestRiskSeq) return false;
    this.latestRisk = r;
    this.latestRiskSeq = seq;
    this.latestRiskSent = false;
    return true;
  }
}

// ---------------------------------------------------------------- crisis (TSD), never throws
export async function checkCrisis(
  idToken: string,
  input: { text?: string; audio?: Blob; video?: Blob; language?: string; turnId: string },
): Promise<CrisisResult | null> {
  if (!CRISIS_BASE) return null;
  const form = new FormData();
  // Contract: do not send typed text together with audio.
  if (input.text && !input.audio) form.append('text', input.text);
  if (input.audio) form.append('audio', input.audio);
  if (input.video) form.append('video', input.video);
  if (input.language) form.append('language', input.language);
  form.append('turn_id', input.turnId);
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), CRISIS_TIMEOUT_MS);
  try {
    const res = await fetch(`${CRISIS_BASE}/api/v1/crisis`, {
      method: 'POST', headers: { Authorization: `Bearer ${idToken}` }, body: form, signal: ctrl.signal,
    });
    if (!res.ok) return null;             // error = "no score this turn", never LOW
    return (await res.json()) as CrisisResult;
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

// ---------------------------------------------------------------- chat SSE
async function streamChat(
  idToken: string,
  body: Record<string, unknown>,
  h: ChatHandlers,
): Promise<ChatResult> {
  const res = await fetch(`${CHAT_BASE}/api/v1/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${idToken}` },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`/api/v1/chat returned ${res.status}: ${text.slice(0, 300)}`);
  }
  if (!res.body) throw new Error('/api/v1/chat returned no response body');

  const out: ChatResult = {
    fullText: '', companionState: { emotion: 'neutral', intensity: 0.4 }, exerciseState: null,
    uiActions: [], handoff: null, latencyMs: null,
  };
  let sawText = false;
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';

  const handle = (event: string, data: Record<string, unknown>) => {
    switch (event) {
      case 'latency':
        out.latencyMs = typeof data.latency_ms === 'number' ? data.latency_ms : null; break;
      case 'companion_state':
        out.companionState = toCompanionState(data); h.onCompanionState?.(out.companionState); break;
      case 'delta': {
        const t = typeof data.text === 'string' ? data.text : '';
        if (t) { sawText = true; out.fullText += t; h.onDelta?.(t); }
        break;
      }
      case 'ui_action': {
        const a: UiAction = { name: String(data.name ?? ''), args: (data.args ?? {}) as Record<string, unknown> };
        out.uiActions.push(a); h.onUiAction?.(a, !sawText); break;  // before any text = urgent (stop/pause)
      }
      case 'handoff':
        if (data.to === 'crisis') { out.handoff = { to: 'crisis', reason: String(data.reason ?? '') }; h.onHandoff?.(out.handoff); }
        break;
      case 'state':
        if (typeof data.exercise_state === 'string') out.exerciseState = data.exercise_state; break;
      case 'done':
        if (typeof data.full_text === 'string' && data.full_text) out.fullText = data.full_text;
        if (data.companion_state) out.companionState = toCompanionState(data.companion_state);
        if (typeof data.exercise_state === 'string') out.exerciseState = data.exercise_state;
        break;
      default: break;                       // contract: ignore unknown events
    }
  };

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const frames = buffer.split('\n\n');
    buffer = frames.pop() ?? '';
    for (const frame of frames) {
      let event = 'message';
      const dataLines: string[] = [];
      for (const line of frame.split('\n')) {
        if (line.startsWith('event:')) event = line.slice(6).trim();
        else if (line.startsWith('data:')) dataLines.push(line.slice(5).trimStart());
      }
      if (!dataLines.length) continue;
      try { handle(event, JSON.parse(dataLines.join('\n'))); }
      catch { console.warn('[KOI] Unparseable SSE frame, skipping'); }
    }
  }
  return out;
}

// ---------------------------------------------------------------- persistence (unchanged from the draft)
async function saveMessage(record: MessageRecord, uid: string): Promise<void> {
  const { secret, saltB64 } = await getActiveCryptoContext(uid);
  const encryptedRecord: MessageRecord = { ...record, content: await encrypt(record.content, secret, saltB64) };
  await db.messages.put(encryptedRecord);
  syncQueue.enqueue({
    collection: `conversations/${record.conversationId}/messages`,
    docId: record.id,
    data: encryptedRecord as unknown as Record<string, unknown>,
    priority: 3,
  });
}

export interface SendMessageResult {
  reply: string;
  companionState: CompanionState;
  uiActions: UiAction[];
  handoff: Handoff | null;
  latencyMs: number | null;
}

/**
 * One user turn. Fires the crisis check in parallel (not awaited before the reply), streams the chat reply,
 * and updates `conv` (exercise_state, risk bookkeeping, crisis flow).
 * Callers: drive the avatar from handlers.onCompanionState, speak each onDelta sentence, run ui actions
 * (start_breathing args: inhale_s / exhale_s / cycles / cue_audio), open UX Flow 4 on onHandoff or onCrisis.
 */
export async function sendMessage(
  userId: string,
  conversationId: string,
  text: string,
  context: ChatTurn[],
  conv: KoiConversationState,
  handlers: ChatHandlers & { onCrisis?: (r: CrisisResult) => void } = {},
  media?: { audio?: Blob; video?: Blob; language?: string },
): Promise<SendMessageResult> {
  const userMsgId = uuidv4();
  await saveMessage({
    id: userMsgId, conversationId, sender: 'user', content: text, timestamp: new Date(),
    emotion: 'neutral', emotion_confidence: 1, synced: false,
  } as MessageRecord, userId);

  try {
    const user = getAuth().currentUser;
    if (!user) throw new Error('No authenticated Firebase user -- cannot call /api/v1/chat');
    const idToken = await user.getIdToken();

    // TSD in parallel, never awaited before the reply (Blueprint §4.1d/§4.1e).
    const seq = ++conv.turnSeq;
    void checkCrisis(idToken, { text, ...media, turnId: userMsgId }).then((r) => {
      if (!r || !conv.acceptRisk(r, seq)) return;       // no score this turn / stale: keep the previous indicator
      if ((r.risk_category === 'HIGH' || r.risk_category === 'CRITICAL') && !conv.crisisFlowOpen) {
        conv.crisisFlowOpen = true;
        handlers.onCrisis?.(r);                         // stop any animation, open UX Flow 4 with intervention_content
      }
    });

    const body: Record<string, unknown> = {
      message: text,
      session_history: context,
      exercise_state: conv.exerciseState,
      client_event: conv.pendingClientEvent,
    };
    if (conv.latestRisk) {
      const r = conv.latestRisk;
      body.risk = { risk_category: r.risk_category, crisis_score: r.crisis_score,
                    trigger_flags: r.trigger_flags, is_new: !conv.latestRiskSent };
    }
    if (conv.pendingCrisisResolution) {
      body.policy_event = 'crisis_resolved';
      body.crisis_path = conv.pendingCrisisResolution;
    }

    const result = await streamChat(idToken, body, {
      ...handlers,
      onHandoff: (h) => {
        if (!conv.crisisFlowOpen) { conv.crisisFlowOpen = true; handlers.onHandoff?.(h); }  // idempotent
      },
    });

    // Request accepted: clear the one-shot fields.
    conv.pendingClientEvent = 'none';
    conv.pendingCrisisResolution = null;
    if (conv.latestRisk) conv.latestRiskSent = true;
    conv.exerciseState = result.exerciseState ?? conv.exerciseState;

    await saveMessage({
      id: uuidv4(), conversationId, sender: 'ai', content: result.fullText, timestamp: new Date(),
      emotion: result.companionState.emotion, emotion_confidence: 1, synced: false,
    } as MessageRecord, userId);

    return { reply: result.fullText, companionState: result.companionState, uiActions: result.uiActions,
             handoff: result.handoff, latencyMs: result.latencyMs };
  } catch (err) {
    console.error('[KOI] sendMessage failed:', err);
    const fallbackReply = "I'm having a little trouble connecting right now. I'm still here with you.";
    await saveMessage({
      id: uuidv4(), conversationId, sender: 'ai', content: fallbackReply, timestamp: new Date(),
      emotion: 'neutral', emotion_confidence: 1, synced: false,
    } as MessageRecord, userId);
    return { reply: fallbackReply, companionState: { emotion: 'neutral', intensity: 0.4 }, uiActions: [],
             handoff: null, latencyMs: null };
  }
}
