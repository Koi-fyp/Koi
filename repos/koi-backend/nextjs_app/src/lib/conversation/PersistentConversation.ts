import { onAuthStateChanged } from 'firebase/auth';
import type { Transaction } from 'dexie';
import { db, type ConversationArchiveRecord, type ConversationRecord } from '../db';
import { auth } from '../firebase';
import { decrypt, encrypt, getActiveCryptoContext, type AuthState } from '../crypto';
import { ConversationSession, type SessionMessage } from './ConversationSession';
import { CompletionLeaseError, readPersistedTurnEvidence } from './persistedEvidence';
import type { ChatAdapter } from './chatContract';
import type { ConversationCompletionEvidence } from '../activities/conversationCompletion';

export type ConversationSwitchReason = 'busy' | 'owner-changed' | 'conflict' | 'storage-unavailable' | 'not-found' | 'locked';
export class ConversationSwitchError extends Error {
  constructor(readonly reason: ConversationSwitchReason) { super(`Conversation switch failed: ${reason}.`); }
}

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
  private state = { loading: true, error: null as string | null, completing: false, switching: false,
    /** Read from saved rows, never from session memory: see persistedEvidence. */
    hasQualifyingPair: false, hasUnresolvedHandoff: false };
  constructor(readonly uid: string, private adapter: ChatAdapter, private authState: AuthState) {}
  getSnapshot = () => this.state;
  subscribe = (fn: () => void) => { this.listeners.add(fn); return () => { this.listeners.delete(fn); }; };
  /** Non-secret metadata of the active header, for History. */
  getActiveHeader() { return this.record ? { conversationId: this.record.conversationId, createdAt: this.record.createdAt, lastActiveAt: this.record.lastActiveAt } : null; }
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
      const session = await this.restoreSession(this.record);
      this.session = session; this.observe(session);
      await this.refreshEvidence(session); this.assertActive();
      session.setReady(true); this.notify({ loading: false });
    } catch {
      if (!this.stopped) { this.session?.dispose(); this.session = null; this.notify({ loading: false, error: 'Conversation history could not be unlocked or saved. Reload after unlocking your account or restoring local storage access.' }); }
    }
  }
  /** Builds a session from an owned header: decrypts its snapshot and reconciles owned saved rows. */
  private async restoreSession(record: ConversationRecord): Promise<ConversationSession> {
    if (record.uid !== this.uid) throw new Error('Foreign conversation');
    const session = new ConversationSession({ send: async (request, options) => {
      this.assertActive();
      // Commit pending user turn before inference. Refresh must never replay a POST.
      await this.checkpoint(); this.assertActive();
      try {
        const result = await this.adapter.send(request, options);
        await this.checkpoint(); this.assertActive();
        return result;
      } finally { void this.refreshEvidence(session); }
    } }, record.conversationId);
    session.setReady(false);
    try {
      if (record.encryptedState) {
        const recovered = JSON.parse(await decrypt(record.encryptedState, this.secret));
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
      return session;
    } catch (error) { session.dispose(); throw error; }
  }
  private observe(session: ConversationSession) {
    this.unsubscribe = session.subscribe(() => {
      const snapshot = session.getSnapshot();
      const last = snapshot.serverEvents[snapshot.serverEvents.length - 1]?.event.event;
      // Persist safety/exercise state during a stream, but never checkpoint each text delta.
      if (!snapshot.pending || (last && ['risk', 'handoff', 'ui_action', 'state', 'done'].includes(last))) {
        void this.checkpoint().catch(() => {});
      }
    });
  }
  /** New Chat: archive the current conversation (an empty one is not archived) and start an empty one. */
  archiveAndStartNew(uid: string) { return this.switchTo(uid, null); }
  /** Resume an archived conversation, archiving the current one. */
  activateArchived(uid: string, targetId: string) { return this.switchTo(uid, targetId); }
  /**
   * One Dexie rw transaction over conversations + conversationArchive moves header ciphertext verbatim.
   * The target is decrypted only before the transaction, to refuse a locked target; the expected
   * active conversationId/revision makes a stale tab fail closed. Nothing is published before commit.
   */
  private async switchTo(uid: string, targetId: string | null): Promise<{ conversationId: string; previousConversationId: string }> {
    const ownerOk = () => !this.stopped && uid === this.uid && auth?.currentUser?.uid === this.uid;
    if (!ownerOk()) throw new ConversationSwitchError('owner-changed');
    const previous = this.session;
    if (!previous || !this.record || this.state.loading || this.state.error) throw new ConversationSwitchError('storage-unavailable');
    if (this.state.switching || this.state.completing || previous.getSnapshot().pending) throw new ConversationSwitchError('busy');
    if (targetId !== null && (!targetId.trim() || targetId.length > 160)) throw new ConversationSwitchError('not-found');
    const empty = previous.getSnapshot().messages.length === 0;
    if (targetId === previous.conversationId || (targetId === null && empty)) {
      return { conversationId: previous.conversationId, previousConversationId: previous.conversationId };
    }
    // Synchronous lease before the first await: sends, completion and a second switch all wait.
    this.notify({ switching: true }); previous.setReady(false); this.unsubscribe?.(); this.unsubscribe = undefined;
    let candidate: ConversationSession | null = null;
    let transaction: Transaction | undefined;
    let ownerChanged = false;
    const stopOwnerWatch = auth ? onAuthStateChanged(auth, user => { if (user?.uid !== this.uid) { ownerChanged = true; transaction?.abort(); } }) : () => {};
    const guard = () => { if (ownerChanged || !ownerOk()) throw new ConversationSwitchError('owner-changed'); };
    try {
      const expected = this.record;
      try { await this.checkpoint(); } catch {
        guard();
        const header = await db.conversations.get(uid).catch(() => undefined);
        throw new ConversationSwitchError(header && (header.conversationId !== expected.conversationId || header.revision !== expected.revision) ? 'conflict' : 'storage-unavailable');
      }
      guard();
      const flushed = this.record!;
      let archived: ConversationArchiveRecord | undefined;
      let target: ConversationRecord;
      if (targetId === null) {
        target = { uid, conversationId: crypto.randomUUID(), createdAt: new Date(), lastActiveAt: new Date(), status: 'active', revision: 0 };
      } else {
        try { archived = await db.conversationArchive.get([uid, targetId]); } catch { guard(); throw new ConversationSwitchError('storage-unavailable'); }
        guard();
        if (!archived || archived.uid !== uid || archived.conversationId !== targetId) throw new ConversationSwitchError('not-found');
        const { archivedAt: _archivedAt, ...header } = archived;
        target = header;
      }
      try { candidate = await this.restoreSession(target); } catch { guard(); throw new ConversationSwitchError('locked'); }
      guard();
      // Monotonic active revision even for A -> B -> A, so a stale tab can never match again.
      const next: ConversationRecord = { ...target, status: 'active', revision: flushed.revision + 1 };
      try {
        await db.transaction('rw', db.conversations, db.conversationArchive, async tx => {
          transaction = tx; guard();
          const current = await db.conversations.get(uid); guard();
          if (!current || current.conversationId !== flushed.conversationId || current.revision !== flushed.revision) throw new ConversationSwitchError('conflict');
          if (archived) {
            const still = await db.conversationArchive.get([uid, archived.conversationId]); guard();
            if (!still || still.encryptedState !== archived.encryptedState) throw new ConversationSwitchError('conflict');
            await db.conversationArchive.delete([uid, archived.conversationId]); guard();
          }
          if (!empty) { await db.conversationArchive.put({ ...current, archivedAt: new Date() }); guard(); }
          await db.conversations.put(next); guard();
        });
      } catch (error) {
        if (error instanceof ConversationSwitchError) throw error;
        throw new ConversationSwitchError(ownerChanged || !ownerOk() ? 'owner-changed' : 'storage-unavailable');
      }
      transaction = undefined;
      guard();
      const published = candidate; candidate = null;
      this.record = next; this.session = published;
      previous.dispose(); this.observe(published); published.setReady(true);
      this.notify({ switching: false, error: null, hasQualifyingPair: false, hasUnresolvedHandoff: false });
      await this.refreshEvidence(published);
      return { conversationId: next.conversationId, previousConversationId: previous.conversationId };
    } catch (error) {
      candidate?.dispose();
      if (!this.stopped && this.session === previous) {
        if (!this.unsubscribe) this.observe(previous);
        previous.setReady(!this.state.error && !ownerChanged);
        this.notify({ switching: false });
      }
      throw error instanceof ConversationSwitchError ? error : new ConversationSwitchError('storage-unavailable');
    } finally { stopOwnerWatch(); }
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
    if (this.state.completing || this.state.switching) throw new CompletionLeaseError('busy');
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
    const session = this.session;
    if (!session || !this.record || this.stopped) return Promise.reject(new Error('Session unavailable'));
    const serialized = JSON.stringify({ ownerUid: this.uid, ...session.recoveryState() });
    const write = this.writes.then(async () => {
      this.assertActive();
      // A session swapped out after its final pre-switch flush never writes into the new header.
      if (this.session !== session) return;
      const encryptedState = await encrypt(serialized, this.secret, this.salt);
      this.assertActive();
      if (this.session !== session) return;
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
