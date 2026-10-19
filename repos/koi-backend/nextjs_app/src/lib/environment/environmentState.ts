import type { ConversationSession, SessionSnapshot } from '../conversation/ConversationSession';
import { environmentEmotion, type EnvironmentMood, type AvatarEnvironmentEmotion } from './palette';

/** Presentation observer only. Never included in conversation recovery or storage. */
export class EnvironmentState {
  private emotion: AvatarEnvironmentEmotion = 'neutral';
  private crisis = false;
  private dialog = false;
  private breathing = false;
  private mood: EnvironmentMood = 'neutral';
  private listeners = new Set<() => void>();
  private owner: object | null = null;
  subscribe = (listener: () => void) => { this.listeners.add(listener); return () => { this.listeners.delete(listener); }; };
  getSnapshot = () => this.mood;
  private publish() {
    const next = this.crisis || this.dialog || this.breathing ? 'calm' : this.emotion;
    if (next !== this.mood) { this.mood = next; this.listeners.forEach(listener => listener()); }
  }
  bind(session: ConversationSession) {
    const owner = {}; this.owner = owner;
    this.emotion = 'neutral'; this.dialog = false; this.breathing = false; this.crisis = false;
    let previous = session.getSnapshot();
    let lastId = Math.max(0, ...previous.serverEvents.map(item => item.id));
    const observe = (snapshot: SessionSnapshot, live: boolean) => {
      const crisis = !!snapshot.policyPathPending || snapshot.serverEvents.some(({ event }) =>
        (event.event === 'handoff' && !session.isHandoffResolved(event.data))
        || (event.event === 'risk' && event.data.status === 'ok' && ['HIGH', 'CRITICAL'].includes(event.data.risk_category)));
      // The existing session clears old events and the queued resolution together.
      // This is a visual reset, never a safety clearance.
      if (this.crisis && !crisis) this.emotion = 'neutral';
      this.crisis = crisis;
      let receivedEmotion = false;
      for (const { id, event } of snapshot.serverEvents) {
        if (id <= lastId) continue;
        lastId = id;
        if (live && (event.event === 'companion_state' || event.event === 'done')) {
          this.emotion = environmentEmotion(event.event === 'done' ? event.data.companion_state.emotion : event.data.emotion);
          receivedEmotion = true;
        }
      }
      // JSON fallback has no SSE events. Only accept a newly completed live turn.
      if (live && !receivedEmotion && previous.pending && !snapshot.pending && !snapshot.error
        && snapshot.messages.some(message => message.sender === 'ai' && message.status === 'completed'
          && previous.messages.some(old => old.id === message.id && old.status === 'pending'))) {
        this.emotion = environmentEmotion(snapshot.companion.emotion);
      }
      previous = snapshot; this.publish();
    };
    observe(previous, false);
    const unsubscribe = session.subscribe(() => { if (this.owner === owner) observe(session.getSnapshot(), true); });
    return {
      breathing: (active: boolean) => { if (this.owner === owner) { this.breathing = active; this.publish(); } },
      dialog: (open: boolean) => { if (this.owner === owner) { this.dialog = open; this.publish(); } },
      dispose: () => {
        unsubscribe();
        if (this.owner === owner) {
          this.owner = null; this.emotion = 'neutral'; this.crisis = false; this.dialog = false; this.breathing = false; this.publish();
        }
      },
    };
  }
}
