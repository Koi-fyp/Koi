import { createChatRequest, parseChatResponse, chatErrorMessage, type ChatAdapter, type CompanionState } from './chatContract';
import type { ConversationState } from '../../components/avatar/VRMAvatarController';
export interface SessionMessage {
  id: string; conversationId: string; sender: 'user' | 'ai'; content: string; timestamp: Date;
  status: 'completed' | 'pending' | 'failed' | 'cancelled'; companion_state?: CompanionState;
}
export interface SessionSnapshot {
  messages: SessionMessage[]; pending: boolean; error: string | null; companion: CompanionState;
  conversationState: ConversationState; subtitle: string; latencyMs: number | null;
}
/** Single conversation source of truth; no auth, storage, media, timers or backend selection. */
export class ConversationSession {
  private snapshot: SessionSnapshot;
  private abort: AbortController | null = null;
  private version = 0; private active = true; private disposed = false;
  private listeners = new Set<() => void>();
  constructor(private readonly adapter: ChatAdapter, readonly conversationId = crypto.randomUUID(), messages: SessionMessage[] = []) {
    this.snapshot = { messages, pending: false, error: null, companion: { emotion: 'neutral', intensity: 0 }, conversationState: 'idle', subtitle: '', latencyMs: null };
  }
  getSnapshot = () => this.snapshot;
  subscribe = (listener: () => void) => { this.listeners.add(listener); return () => { this.listeners.delete(listener); }; };
  private patch(update: Partial<SessionSnapshot>) { this.snapshot = { ...this.snapshot, ...update }; if (this.active) this.listeners.forEach((listener) => listener()); }
  activate() { if (!this.disposed) this.active = true; }
  deactivate() { this.cancel(); this.active = false; }
  replaceMessages(messages: SessionMessage[]) { if (!this.disposed && this.active && !this.snapshot.pending) this.patch({ messages }); }
  inputFocused(focused: boolean) { if (!this.disposed && this.active && !this.snapshot.pending) this.patch({ conversationState: focused ? 'listening' : 'idle' }); }
  async send(text: string): Promise<void> {
    if (this.disposed || !this.active || !text.trim()) return;
    this.cancel();
    const request = createChatRequest(text, this.snapshot.messages.filter((message) => message.status === 'completed').slice(-5)
      .map((message) => ({ role: message.sender === 'user' ? 'user' : 'assistant', content: message.content })));
    const version = ++this.version; const abort = new AbortController(); this.abort = abort;
    const userMessageId = crypto.randomUUID(), assistantMessageId = crypto.randomUUID();
    const user: SessionMessage = { id: userMessageId, conversationId: this.conversationId, sender: 'user', content: request.message, timestamp: new Date(), status: 'pending' };
    this.patch({ messages: [...this.snapshot.messages, user], pending: true, error: null, conversationState: 'thinking' });
    try {
      const result = parseChatResponse(await this.adapter.send(request, {
        signal: abort.signal, userMessageId, assistantMessageId,
        onEvent: (event, payload) => {
          if (event === 'companion_state') this.patch({ companion: parseChatResponse({ reply: 'event', latency_ms: 0, companion_state: payload }).companion_state });
          if (event === 'delta' && typeof payload.text === 'string') this.patch({ subtitle: payload.text, conversationState: 'speaking' });
        },
      }));
      if (abort.signal.aborted || version !== this.version || !this.active || this.disposed) return;
      this.patch({ messages: [...this.snapshot.messages.map((message) => message.id === userMessageId ? { ...message, status: 'completed' as const } : message),
        { id: assistantMessageId, conversationId: this.conversationId, sender: 'ai', content: result.reply, timestamp: new Date(), status: 'completed', companion_state: result.companion_state }],
        companion: result.companion_state, subtitle: result.reply, latencyMs: result.latency_ms,
        pending: false, conversationState: 'speaking' }); // Visual response display only; no audio.
    } catch (error) {
      if (version !== this.version || !this.active || this.disposed || abort.signal.aborted) return;
      this.patch({ messages: this.snapshot.messages.map((message) => message.id === userMessageId ? { ...message, status: 'failed' as const } : message),
        pending: false, error: chatErrorMessage(error), conversationState: 'idle', companion: { emotion: 'neutral', intensity: 0 } });
    } finally { if (version === this.version) this.abort = null; }
  }
  cancel() {
    this.version++; this.abort?.abort(); this.abort = null;
    if (this.snapshot.pending) this.patch({ pending: false, conversationState: 'idle', messages: this.snapshot.messages.map((message) => message.status === 'pending' ? { ...message, status: 'cancelled' as const } : message) });
  }
  dispose() { if (this.disposed) return; this.deactivate(); this.disposed = true; this.listeners.clear(); }
}
