import type { SpeechFrame, SpeechTimeline } from './mouthCues';
import type { PlaybackSnapshot, SpeechSource } from './SpeechPlayback';
import { parseGuardedSpeech, SpeechGuardError, voiceFor, type SpeechCompanion, type SpeechLanguage } from './voiceGuard';
export type SpeechCancelReason = 'stop' | 'new-turn' | 'avatar-switch' | 'unmount' | 'logout' | 'crisis-handoff' | 'exercise-stop';
export type SpeechTurnStatus = 'idle' | 'requesting' | 'speaking' | 'done' | 'failed' | 'cancelled';
export interface SpeechTurnSnapshot { status: SpeechTurnStatus; generationId: string | null; reason: SpeechCancelReason | null; error: string | null; canRetry: boolean; }
export interface SpeechRequest { text: string; voice_id: string; language: SpeechLanguage; generation_id: string; }
export interface SpeechTurn { text: string; companion: SpeechCompanion; language: SpeechLanguage; }
/** The subset of SpeechPlayback used here, so tests can drive a fake media clock. */
export interface TurnPlayback extends SpeechTimeline {
  load(source: SpeechSource): void; play(): Promise<void>; clear(): void; dispose(): void;
  getSnapshot(): PlaybackSnapshot; subscribe(listener: () => void): () => void;
}
export interface SpeechTurnOptions {
  playback: TurnPlayback;
  // Injected transport; this module never chooses an endpoint or performs network I/O itself.
  fetchSpeech: (request: SpeechRequest, signal: AbortSignal) => Promise<unknown>;
  newGenerationId?: () => string;
}
const FAILED = 'Voice is unavailable for this reply. The text above is complete.';
const IDLE: SpeechFrame = Object.freeze({ active: false, time: 0, cues: Object.freeze([]) });
/**
 * One speech turn at a time. Owns only audio + cues: chat text is read once and never written.
 * Every cancel path aborts the request, invalidates the generation and clears the playback, so the
 * mouth falls back to neutral on the next frame of the existing render loop.
 */
export class SpeechTurnController implements SpeechTimeline {
  private readonly playback: TurnPlayback;
  private readonly fetchSpeech: SpeechTurnOptions['fetchSpeech'];
  private readonly newId: () => string;
  private abort?: AbortController;
  private generation = 0;
  private turn?: SpeechTurn;
  private companion?: SpeechCompanion;
  private disposed = false;
  private snapshot: SpeechTurnSnapshot = { status: 'idle', generationId: null, reason: null, error: null, canRetry: false };
  private listeners = new Set<() => void>();
  private unsubscribePlayback: () => void;
  constructor({ playback, fetchSpeech, newGenerationId }: SpeechTurnOptions) {
    this.playback = playback; this.fetchSpeech = fetchSpeech;
    let counter = 0;
    this.newId = newGenerationId ?? (() => (typeof crypto !== 'undefined' && 'randomUUID' in crypto ? crypto.randomUUID() : `gen-${Date.now()}-${++counter}`));
    this.unsubscribePlayback = playback.subscribe(this.onPlayback);
  }
  getSnapshot = () => this.snapshot;
  subscribe = (listener: () => void) => { this.listeners.add(listener); return () => { this.listeners.delete(listener); }; };
  private publish(next: Partial<SpeechTurnSnapshot>) {
    if (this.disposed) return;
    this.snapshot = { ...this.snapshot, ...next };
    this.listeners.forEach(listener => listener());
  }
  private onPlayback = () => {
    if (this.disposed || this.snapshot.status !== 'speaking') return;
    const state = this.playback.getSnapshot().state;
    // Status changes before clear(): clearing re-publishes media events, which must not re-enter here.
    if (state === 'ended') { this.publish({ status: 'done' }); this.playback.clear(); }
    else if (state === 'error') this.fail();
  };
  private fail() { this.publish({ status: 'failed', error: FAILED, canRetry: !!this.turn }); this.playback.clear(); }
  /** Media clock only: inactive (and cue-less) whenever there is no current, playing turn. */
  getFrame(): SpeechFrame { return this.disposed || this.snapshot.status !== 'speaking' ? IDLE : this.playback.getFrame(); }
  /** Avatar switch cancels a turn spoken in another companion's voice. */
  setCompanion(companion: SpeechCompanion | undefined) {
    if (this.disposed || companion === this.companion) return;
    this.companion = companion;
    if (this.turn && this.turn.companion !== companion) { this.cancel('avatar-switch'); this.turn = undefined; this.publish({ canRetry: false }); }
  }
  async speak(turn: SpeechTurn) {
    if (this.disposed) return;
    this.cancel('new-turn');
    this.turn = Object.freeze({ ...turn });
    const generation = this.generation, generationId = this.newId();
    let voiceId: string;
    try {
      voiceId = voiceFor(turn.companion, turn.language);
      if (this.companion && this.companion !== turn.companion) throw new SpeechGuardError('voice-mismatch', 'Turn companion is not the active avatar.');
    } catch { this.publish({ generationId, reason: null }); this.fail(); return; }
    const abort = this.abort = new AbortController();
    this.publish({ status: 'requesting', generationId, reason: null, error: null, canRetry: false });
    try {
      const response = await this.fetchSpeech({ text: turn.text, voice_id: voiceId, language: turn.language, generation_id: generationId }, abort.signal);
      if (generation !== this.generation || this.disposed) return;
      const speech = await parseGuardedSpeech(response, { companion: turn.companion, language: turn.language, generationId });
      if (generation !== this.generation || this.disposed) return;
      this.playback.load({ audioBlob: speech.audio, mouthCues: speech.cues });
      this.publish({ status: 'speaking' });
      await this.playback.play();
      if (generation !== this.generation || this.disposed) return;
      if (this.playback.getSnapshot().state === 'error') this.fail();
    } catch {
      if (generation === this.generation && !this.disposed) this.fail();
    } finally { if (this.abort === abort) this.abort = undefined; }
  }
  retry() { if (!this.disposed && this.snapshot.status === 'failed' && this.turn) return this.speak(this.turn); }
  cancel(reason: SpeechCancelReason) {
    if (this.disposed) return;
    this.generation++;
    this.abort?.abort(); this.abort = undefined;
    this.playback.clear();
    if (this.snapshot.status === 'requesting' || this.snapshot.status === 'speaking') this.publish({ status: 'cancelled', reason, error: null, canRetry: false });
  }
  dispose() {
    if (this.disposed) return;
    this.cancel('unmount');
    this.unsubscribePlayback(); this.playback.dispose();
    this.turn = undefined; this.listeners.clear(); this.disposed = true;
    this.snapshot = { status: 'cancelled', generationId: null, reason: 'unmount', error: null, canRetry: false };
  }
}
