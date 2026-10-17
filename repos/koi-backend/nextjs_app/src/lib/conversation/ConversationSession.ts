import { createChatRequest, parseChatResponse, chatErrorMessage, type ChatAdapter, type ChatServerEvent, type CompanionState, type ExerciseClientEvent, type CrisisPath } from './chatContract';
import type { ConversationState } from '../../components/avatar/VRMAvatarController';
export interface SessionMessage {
  id: string; conversationId: string; sender: 'user' | 'ai'; content: string; timestamp: Date;
  status: 'completed' | 'pending' | 'failed' | 'cancelled'; companion_state?: CompanionState;
}
export interface SessionSnapshot {
  messages: SessionMessage[]; pending: boolean; error: string | null; companion: CompanionState;
  conversationState: ConversationState; subtitle: string; latencyMs: number | null;
  exerciseState: string | null;
  clientEventPending: ExerciseClientEvent | null;
  policyPathPending: CrisisPath | null;
  serverEvents: Array<{ id: number; event: ChatServerEvent }>;
}
/** Single conversation source of truth; no auth, storage, media, timers or backend selection. */
export class ConversationSession {
  private snapshot: SessionSnapshot;
  private abort: AbortController | null = null;
  private version = 0; private active = true; private disposed = false;
  private eventSequence = 0;
  private seenUiActionKeys = new Set<string>();
  private seenHandoffKeys = new Set<string>();
  private resolvedHandoffKeys = new Set<string>();
  private listeners = new Set<() => void>();
  constructor(private readonly adapter: ChatAdapter, readonly conversationId = crypto.randomUUID(), messages: SessionMessage[] = []) {
    this.snapshot = { messages, pending: false, error: null, companion: { emotion: 'neutral', intensity: 0 }, conversationState: 'idle', subtitle: '', latencyMs: null,
      exerciseState: null, clientEventPending: null, policyPathPending: null, serverEvents: [] };
  }
  getSnapshot = () => this.snapshot;
  subscribe = (listener: () => void) => { this.listeners.add(listener); return () => { this.listeners.delete(listener); }; };
  private patch(update: Partial<SessionSnapshot>) { this.snapshot = { ...this.snapshot, ...update }; if (this.active) this.listeners.forEach((listener) => listener()); }
  activate() { if (!this.disposed) this.active = true; }
  deactivate() { this.cancel(); this.active = false; }
  replaceMessages(messages: SessionMessage[]) { if (!this.disposed && this.active && !this.snapshot.pending) this.patch({ messages }); }
  inputFocused(focused: boolean) { if (!this.disposed && this.active && !this.snapshot.pending) this.patch({ conversationState: focused ? 'listening' : 'idle' }); }
  queueClientEvent(event: ExerciseClientEvent) {
    if (!this.disposed && this.active && !this.snapshot.clientEventPending) this.patch({ clientEventPending: event });
  }
  queueCrisisPath(path: CrisisPath, handoff: { to: 'crisis'; reason: string }) {
    if (!this.disposed && this.active && !this.snapshot.policyPathPending) {
      this.resolvedHandoffKeys.add(JSON.stringify([handoff.to, handoff.reason]));
      this.patch({ policyPathPending: path });
    }
  }
  sendClientEvent(event: ExerciseClientEvent): Promise<void> {
    const messages: Record<ExerciseClientEvent, string> = {
      playback_done: 'I completed the breathing exercise.',
      playback_stopped: 'I stopped the breathing exercise.',
      start_breathing: 'I would like to try the breathing exercise.',
      start_grounding: 'I would like to try the grounding activity.',
      start_plan: 'I would like to try making a small plan.',
    };
    if (this.snapshot.clientEventPending && this.snapshot.clientEventPending !== event) {
      this.patch({ error: 'Send a message to deliver the pending exercise update before requesting another activity.' });
      return Promise.resolve();
    }
    return this.send(messages[event], event);
  }
  async send(text: string, explicitClientEvent?: ExerciseClientEvent): Promise<void> {
    if (this.disposed || !this.active || !text.trim()) return;
    this.cancel();
    const clientEvent = explicitClientEvent ?? this.snapshot.clientEventPending ?? undefined;
    const policyPath = this.snapshot.policyPathPending ?? undefined;
    const request = createChatRequest(text, this.snapshot.messages.filter((message) => message.status === 'completed').slice(-5)
      .map((message) => ({ role: message.sender === 'user' ? 'user' : 'assistant', content: message.content })), {
        exercise_state: this.snapshot.exerciseState,
        ...(clientEvent ? { client_event: clientEvent } : {}),
        ...(policyPath ? { policy_event: 'crisis_resolved' as const, crisis_path: policyPath } : {}),
      });
    this.patch({ clientEventPending: null, policyPathPending: null, serverEvents: [] });
    this.seenUiActionKeys.clear(); this.seenHandoffKeys.clear();
    const version = ++this.version; const abort = new AbortController(); this.abort = abort;
    const userMessageId = crypto.randomUUID(), assistantMessageId = crypto.randomUUID();
    const user: SessionMessage = { id: userMessageId, conversationId: this.conversationId, sender: 'user', content: request.message, timestamp: new Date(), status: 'pending' };
    const assistant: SessionMessage = { id: assistantMessageId, conversationId: this.conversationId, sender: 'ai', content: '', timestamp: new Date(), status: 'pending' };
    this.patch({ messages: [...this.snapshot.messages, user, assistant], pending: true, error: null, subtitle: 'Connecting to KOI…', conversationState: 'thinking' });
    try {
      const result = parseChatResponse(await this.adapter.send(request, {
        signal: abort.signal, userMessageId, assistantMessageId,
        onEvent: (event) => {
          if (abort.signal.aborted || version !== this.version || !this.active || this.disposed) return;
          const dispatch = (next: ChatServerEvent) => {
            if (next.event === 'state') this.patch({ exerciseState: next.data.exercise_state });
            if (next.event === 'ui_action') {
              const key = JSON.stringify([next.data.name, next.data.args]);
              if (this.seenUiActionKeys.has(key)) return;
              this.seenUiActionKeys.add(key);
            }
            if (next.event === 'handoff') {
              const key = JSON.stringify([next.data.to, next.data.reason]);
              if (this.resolvedHandoffKeys.has(key)) return;
              if (this.seenHandoffKeys.has(key)) return;
              this.seenHandoffKeys.add(key);
            }
            if (next.event === 'companion_state') this.patch({
              companion: next.data,
              messages: this.snapshot.messages.map((message) => message.id === assistantMessageId ? { ...message, companion_state: next.data } : message),
            });
            if (next.event === 'delta') this.patch({
              subtitle: this.snapshot.subtitle === 'Connecting to KOI…' ? next.data.text : this.snapshot.subtitle + next.data.text,
              messages: this.snapshot.messages.map((message) => message.id === assistantMessageId ? { ...message, content: message.content + next.data.text } : message),
              conversationState: 'speaking',
            });
            if (next.event === 'done') {
              if (Object.prototype.hasOwnProperty.call(next.data, 'exercise_state')) this.patch({ exerciseState: next.data.exercise_state ?? null });
              this.patch({ subtitle: next.data.full_text,
                messages: this.snapshot.messages.map((message) => message.id === assistantMessageId ? { ...message, content: next.data.full_text } : message) });
            }
            this.patch({ serverEvents: [...this.snapshot.serverEvents, { id: ++this.eventSequence, event: next }] });
          };
          if (event.event === 'done') {
            // The server repeats action/handoff summaries in `done`; use them only
            // as fallbacks if their standalone event did not arrive.
            event.data.ui_actions?.forEach((action) => dispatch({ event: 'ui_action', data: action }));
            if (event.data.handoff) dispatch({ event: 'handoff', data: event.data.handoff });
          }
          dispatch(event);
        },
      }));
      if (abort.signal.aborted || version !== this.version || !this.active || this.disposed) return;
      const finalized = this.snapshot.messages.map((message) => message.id === userMessageId
        ? { ...message, status: 'completed' as const }
        : message.id === assistantMessageId
          ? { ...message, content: result.reply, status: 'completed' as const, companion_state: result.companion_state }
          : message);
      if (!finalized.some((message) => message.id === assistantMessageId)) finalized.push({
        id: assistantMessageId, conversationId: this.conversationId, sender: 'ai', content: result.reply,
        timestamp: new Date(), status: 'completed', companion_state: result.companion_state,
      });
      this.patch({ messages: finalized,
        companion: result.companion_state, subtitle: result.reply, latencyMs: result.latency_ms,
        pending: false, conversationState: 'speaking' }); // Visual response display only; no audio.
    } catch (error) {
      if (version !== this.version || !this.active || this.disposed || abort.signal.aborted) return;
      this.patch({ messages: this.snapshot.messages.filter((message) => message.id !== assistantMessageId).map((message) => message.id === userMessageId ? { ...message, status: 'failed' as const } : message),
        pending: false, subtitle: '', error: chatErrorMessage(error), conversationState: 'idle', companion: { emotion: 'neutral', intensity: 0 } });
    } finally { if (version === this.version) this.abort = null; }
  }
  cancel() {
    this.version++; this.abort?.abort(); this.abort = null;
    if (this.snapshot.pending) this.patch({ pending: false, subtitle: '', conversationState: 'idle', companion: { emotion: 'neutral', intensity: 0 }, messages: this.snapshot.messages.filter((message) => !(message.sender === 'ai' && message.status === 'pending')).map((message) => message.status === 'pending' ? { ...message, status: 'cancelled' as const } : message) });
  }
  dispose() { if (this.disposed) return; this.deactivate(); this.disposed = true; this.listeners.clear(); }
}
