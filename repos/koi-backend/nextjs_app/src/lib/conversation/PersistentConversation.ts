import { db, type ConversationRecord } from '../db';
import { decrypt, encrypt, getActiveCryptoContext, type AuthState } from '../crypto';
import { ConversationSession, type SessionMessage } from './ConversationSession';
import { CompletionLeaseError, readPersistedTurnEvidence } from './persistedEvidence';
import type { ChatAdapter } from './chatContract';
import type { ConversationCompletionEvidence } from '../activities/conversationCompletion';

/** One authenticated owner, independent of route subscribers. No transport duplication. */
export class PersistentConversation {
  session: ConversationSession | null = null;
  private record: ConversationRecord | null = null;
  private stopped = false;
  private secret = '';
  private salt = '';
  private writes: Promise<void> = Promise.resolve();
  private unsubscribe?: () => void;
  private listeners = new Set<() => void>();
  private state = { loading: true, error: null as string | null, completing: false,
    /** Read from saved rows, never from session memory: see persistedEvidence. */
    hasQualifyingPair: false, hasUnresolvedHandoff: false };
  constructor(readonly uid: string, private adapter: ChatAdapter, private authState: AuthState) {}
  getSnapshot = () => this.state;
  subscribe = (fn: () => void) => { this.listeners.add(fn); return () => { this.listeners.delete(fn); }; };
  private notify(update: Partial<typeof this.state>) { this.state = { ...this.state, ...update }; this.listeners.forEach(fn => fn()); }
  private assertActive() { if (this.stopped) throw new Error('Owner session ended'); }
  async initialize() {
    try {
      const context = await getActiveCryptoContext(this.uid, this.authState);
      this.assertActive(); this.secret = context.secret; this.salt = context.saltB64;
      this.record = await db.transaction('rw', db.conversations, async () => {
        const existing = await db.conversations.get(this.uid);
        if (existing) return existing;
        const record: ConversationRecord = { uid: this.uid, conversationId: crypto.randomUUID(), createdAt: new Date(), lastActiveAt: new Date(), status: 'active', revision: 0 };
        await db.conversations.add(record); return record;
      });
      this.assertActive();
      const session = new ConversationSession({ send: async (request, options) => {
        this.assertActive();
        // Commit pending user turn before inference. Refresh must never replay a POST.
        await this.checkpoint(); this.assertActive();
        try {
          const result = await this.adapter.send(request, options);
          await this.checkpoint(); this.assertActive();
          return result;
        } finally { void this.refreshEvidence(session); }
      } }, this.record.conversationId);
      this.session = session; session.setReady(false);
      if (this.record.encryptedState) {
        const recovered = JSON.parse(await decrypt(this.record.encryptedState, this.secret));
        this.assertActive();
        if (recovered.ownerUid !== this.uid || !recovered.snapshot || !Array.isArray(recovered.snapshot.messages)
          || recovered.snapshot.messages.some((m: SessionMessage) => m.conversationId !== session.conversationId)) throw new Error('Invalid recovery state');
        session.restore(recovered);
      }
      // Reconcile committed service rows if a refresh raced the final snapshot write.
      // Never adopt v1 rows without ownership, even when their ID happens to match.
      const rows = await db.messages.where('conversationId').equals(session.conversationId).sortBy('timestamp');
      const owned = rows.filter(row => row.ownerUid === this.uid);
      const messages = new Map(session.getSnapshot().messages.map(m => [m.id, m]));
      for (const row of owned) {
        const completed = row.sender === 'ai' || owned.some(reply => reply.replyTo === row.id);
        messages.set(row.id, { ...messages.get(row.id), id: row.id, conversationId: row.conversationId, sender: row.sender,
          content: await decrypt(row.content, this.secret), timestamp: messages.get(row.id)?.timestamp ?? new Date(row.timestamp), status: completed ? 'completed' : 'cancelled',
          companion_state: row.companion_state ?? { emotion: row.emotion === 'happy' ? 'joy' : row.emotion === 'sad' ? 'sorrow' : 'neutral', intensity: 0 } });
      }
      this.assertActive();
      session.replaceMessages([...messages.values()].sort((a,b) => +a.timestamp - +b.timestamp));
      this.unsubscribe = session.subscribe(() => {
        const snapshot = session.getSnapshot();
        const last = snapshot.serverEvents[snapshot.serverEvents.length - 1]?.event.event;
        // Persist safety/exercise state during a stream, but never checkpoint each text delta.
        if (!snapshot.pending || (last && ['risk', 'handoff', 'ui_action', 'state', 'done'].includes(last))) {
          void this.checkpoint().catch(() => {});
        }
      });
      await this.refreshEvidence(session); this.assertActive();
      session.setReady(true); this.notify({ loading: false });
    } catch {
      if (!this.stopped) { this.session?.dispose(); this.session = null; this.notify({ loading: false, error: 'Conversation history could not be unlocked or saved. Reload after unlocking your account or restoring local storage access.' }); }
    }
  }
  private async refreshEvidence(session: ConversationSession) {
    try {
      const evidence = await readPersistedTurnEvidence(this.uid, session.conversationId);
      if (!this.stopped && this.session === session) this.notify({ hasQualifyingPair: !!evidence.pair, hasUnresolvedHandoff: evidence.hasUnresolvedHandoff });
    } catch { /* Keep the last known state; completion re-reads saved rows under its lease. */ }
  }
  /** Holds sends off while one explicit completion reads saved evidence and commits. */
  async withCompletionLease<T>(run: (evidence: ConversationCompletionEvidence) => Promise<T>): Promise<T> {
    const session = this.session;
    if (this.stopped || !session || !this.record || this.state.loading || this.state.error) throw new CompletionLeaseError('unavailable');
    if (this.state.completing) throw new CompletionLeaseError('busy');
    if (session.getSnapshot().pending) throw new CompletionLeaseError('pending');
    this.notify({ completing: true }); session.setReady(false);
    try {
      const { pair, hasUnresolvedHandoff } = await readPersistedTurnEvidence(this.uid, session.conversationId);
      if (this.stopped || this.session !== session) throw new CompletionLeaseError('unavailable');
      this.notify({ hasQualifyingPair: !!pair, hasUnresolvedHandoff });
      return await run({ ownerUid: this.uid, conversationId: session.conversationId, pending: session.getSnapshot().pending,
        lastPersistedMessageId: pair?.lastPersistedMessageId ?? null, persistedExchanges: pair?.persistedExchanges ?? 0,
        turnState: pair ? 'done-persisted' : 'done-unpersisted', handoffState: hasUnresolvedHandoff ? 'unresolved' : 'resolved-or-absent' });
    } finally {
      if (!this.stopped) { if (this.session === session) session.setReady(!this.state.error); this.notify({ completing: false }); }
    }
  }
  checkpoint(): Promise<void> {
    if (!this.session || !this.record || this.stopped) return Promise.reject(new Error('Session unavailable'));
    const serialized = JSON.stringify({ ownerUid: this.uid, ...this.session.recoveryState() });
    const write = this.writes.then(async () => {
      this.assertActive();
      const encryptedState = await encrypt(serialized, this.secret, this.salt);
      this.assertActive();
      await db.transaction('rw', db.conversations, async () => {
        const current = await db.conversations.get(this.uid);
        if (!current || current.conversationId !== this.record!.conversationId || current.revision !== this.record!.revision) throw new Error('Conversation changed in another tab');
        this.assertActive();
        const next = { ...current, encryptedState, revision: current.revision + 1, lastActiveAt: new Date() };
        await db.conversations.put(next); this.record = next;
      });
    });
    this.writes = write.catch(() => {});
    return write.catch(() => {
      if (!this.stopped) { this.session?.setReady(false); this.notify({ error: 'Conversation storage changed or is unavailable. Reload to restore history before sending.' }); }
      throw new Error('Conversation checkpoint failed');
    });
  }
  dispose() {
    this.stopped = true; this.unsubscribe?.(); this.session?.dispose(); this.session = null;
    this.secret = ''; this.salt = ''; this.record = null; this.listeners.clear();
  }
}
