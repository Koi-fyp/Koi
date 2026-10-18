import type { SpeechFrame, SpeechTimeline } from './mouthCues';
import type { TurnPlayback } from './SpeechTurnController';
import { chunkReply, classifyChunk, speakable, type ReplyLanguageHint } from './chunkReply';
import { languageForVoice, type AdaptedSpeech, type SpeechClient, type SpeechClientErrorCode, type SpeechVoiceId } from './speechClient';
import { chooseVoice } from './voiceChoice';
export type ReplyStatusState = 'idle' | 'requesting' | 'playing' | 'skipped' | 'error';
export type ReplyStatusReason = SpeechClientErrorCode | 'timeout' | 'playback-failed' | 'unspeakable' | 'cancelled';
export interface ReplyStatus { state: ReplyStatusState; generationId: string | null; chunk: number | null; total: number; reason: ReplyStatusReason | null; }
export interface ReplyTurn { text: string; companion: string; ownerUid: string; generationId: string; languageHint?: ReplyLanguageHint; }
export type ReplyOutcome = 'completed' | 'silent' | 'cancelled' | 'error';
/** VRMMouthController satisfies this: setSource(undefined) resets every mouth preset to 0. */
export interface ReplyMouth { setSource(source?: SpeechTimeline): void; }
export interface SpeechReplyOptions {
  client: Pick<SpeechClient, 'speak'>;
  playback: TurnPlayback;
  mouth?: ReplyMouth;
  onStatus?: (status: ReplyStatus) => void;
  chunkTimeoutMs?: number;
  /** English cue extraction is slow (~18 s for 163 chars), so chunks are kept near 100 chars, never over 450. */
  chunkMaxChars?: number;
  newRequestId?: () => string;
}
type Planned = { text: string; voice: SpeechVoiceId | null };
type ActiveTurn = { turn: Readonly<ReplyTurn>; abort: AbortController; promise: Promise<ReplyOutcome> };
type ChunkResult = { ok: true; speech: AdaptedSpeech } | { ok: false; reason: ReplyStatusReason };
// Unauthenticated/rate-limited would fail every later chunk too, so they end the turn instead of skipping.
const TERMINAL: ReadonlySet<ReplyStatusReason> = new Set(['unauthenticated', 'rate-limited']);
const IDLE_FRAME: SpeechFrame = Object.freeze({ active: false, time: 0, cues: Object.freeze([]) });
/**
 * Speaks one finished reply chunk by chunk: at most one request in flight, chunk n+1 fetched while n plays.
 * Reads the reply text once and never writes it; a failed or slow chunk is skipped, the text is unaffected.
 */
export class SpeechReplyController implements SpeechTimeline {
  private readonly client: SpeechReplyOptions['client'];
  private readonly playback: TurnPlayback;
  private readonly mouth?: ReplyMouth;
  private readonly onStatus?: SpeechReplyOptions['onStatus'];
  private readonly timeoutMs: number;
  private readonly maxChars: number;
  private readonly newRequestId: () => string;
  private generation = 0;
  private active?: ActiveTurn;
  private playing = false;
  private disposed = false;
  private status: ReplyStatus = { state: 'idle', generationId: null, chunk: null, total: 0, reason: null };
  constructor({ client, playback, mouth, onStatus, chunkTimeoutMs = 12_000, chunkMaxChars = 100, newRequestId }: SpeechReplyOptions) {
    this.client = client; this.playback = playback; this.mouth = mouth; this.onStatus = onStatus;
    this.timeoutMs = chunkTimeoutMs; this.maxChars = chunkMaxChars;
    this.newRequestId = newRequestId ?? (() => globalThis.crypto.randomUUID());
  }
  getStatus = () => this.status;
  getFrame(): SpeechFrame { return !this.disposed && this.playing ? this.playback.getFrame() : IDLE_FRAME; }
  private publish(next: Partial<ReplyStatus>) {
    if (this.disposed) return;
    this.status = { ...this.status, ...next };
    try { this.onStatus?.(this.status); } catch { /* A status consumer must not break speech. */ }
  }
  speakReply(turn: ReplyTurn, { signal }: { signal?: AbortSignal } = {}): Promise<ReplyOutcome> {
    if (this.disposed) return Promise.resolve('cancelled');
    const current = this.active?.turn;
    if (current && current.generationId === turn.generationId && current.ownerUid === turn.ownerUid && current.companion === turn.companion) return this.active.promise;
    this.cancel();
    if (signal?.aborted) return Promise.resolve('cancelled');
    const frozen = Object.freeze({ text: turn.text, companion: turn.companion, ownerUid: turn.ownerUid, generationId: turn.generationId, languageHint: turn.languageHint });
    const generation = this.generation, abort = new AbortController();
    signal?.addEventListener('abort', () => { if (generation === this.generation) this.cancel(); }, { once: true });
    const entry: ActiveTurn = { turn: frozen, abort, promise: Promise.resolve<ReplyOutcome>('cancelled') };
    this.active = entry;
    entry.promise = this.run(frozen, generation, abort.signal);
    return entry.promise;
  }
  /** A different signed-in user or avatar must never hear the previous one's reply. */
  setOwner(ownerUid: string | null | undefined) { if (this.active && this.active.turn.ownerUid !== ownerUid) this.cancel(); }
  setCompanion(companion: string | null | undefined) { if (this.active && this.active.turn.companion !== companion) this.cancel(); }
  /** Invalidates the generation: aborts requests, stops audio (releasing its object URL) and neutralises the mouth. */
  cancel() {
    if (this.disposed) return;
    const had = !!this.active || this.playing;
    this.generation++;
    this.active?.abort.abort(); this.active = undefined; this.playing = false;
    this.playback.clear(); this.mouth?.setSource(undefined);
    if (had) this.publish({ state: 'idle', chunk: null, reason: 'cancelled' });
  }
  dispose() {
    if (this.disposed) return;
    this.cancel(); this.playback.dispose(); this.disposed = true;
  }
  private stale(generation: number) { return generation !== this.generation || this.disposed; }
  private finish(generation: number, final: Partial<ReplyStatus>) {
    if (this.stale(generation)) return;
    this.active?.abort.abort(); this.active = undefined; this.playing = false;
    this.playback.clear(); this.mouth?.setSource(undefined);
    this.publish({ chunk: null, ...final });
  }
  private async run(turn: Readonly<ReplyTurn>, generation: number, signal: AbortSignal): Promise<ReplyOutcome> {
    const plan: Planned[] = chunkReply(turn.text, { maxChars: this.maxChars })
      .map(text => ({ text, voice: speakable(text, turn.languageHint) ? chooseVoice(turn.companion, classifyChunk(text)) : null }));
    const total = plan.length;
    this.publish({ state: 'idle', generationId: turn.generationId, chunk: null, total, reason: null });
    if (!plan.some(chunk => chunk.voice)) { this.finish(generation, { state: 'idle' }); return 'silent'; }
    this.mouth?.setSource(this);
    const nextVoiced = (from: number) => { for (let i = from; i < total; i++) if (plan[i].voice) return i; return -1; };
    let pending = this.request(plan[nextVoiced(0)], signal);
    for (let i = 0; i < total; i++) {
      if (this.stale(generation)) return 'cancelled';
      if (!plan[i].voice) { this.publish({ state: 'skipped', chunk: i, reason: 'unspeakable' }); continue; }
      if (!pending.settled) this.publish({ state: 'requesting', chunk: i, reason: null });
      const result = await pending.promise;
      if (this.stale(generation)) return 'cancelled';
      const next = nextVoiced(i + 1);
      if ('reason' in result && TERMINAL.has(result.reason)) { this.finish(generation, { state: 'error', reason: result.reason }); return 'error'; }
      if (next >= 0) pending = this.request(plan[next], signal);
      if ('reason' in result) { this.publish({ state: 'skipped', chunk: i, reason: result.reason }); continue; }
      const played = await this.play(result.speech, generation, i);
      if (this.stale(generation)) return 'cancelled';
      if (!played) this.publish({ state: 'skipped', chunk: i, reason: 'playback-failed' });
    }
    this.finish(generation, { state: 'idle', reason: null });
    return 'completed';
  }
  /** Never rejects; a turn abort or the per-chunk timeout settles it even if the client ignores its signal. */
  private request(chunk: Planned, turnSignal: AbortSignal) {
    const abort = new AbortController(), voice = chunk.voice!;
    const tracker = { settled: false, promise: undefined as Promise<ChunkResult> | undefined };
    let timer: ReturnType<typeof setTimeout> | undefined, onAbort: (() => void) | undefined;
    const guard = new Promise<ChunkResult>(resolve => {
      timer = setTimeout(() => { abort.abort(); resolve({ ok: false, reason: 'timeout' }); }, this.timeoutMs);
      onAbort = () => { abort.abort(); resolve({ ok: false, reason: 'aborted' }); };
      if (turnSignal.aborted) onAbort(); else turnSignal.addEventListener('abort', onAbort, { once: true });
    });
    const call = Promise.resolve()
      .then(() => this.client.speak({ text: chunk.text, voice_id: voice, language: languageForVoice(voice), generation_id: this.newRequestId() }, { signal: abort.signal }))
      .then((result): ChunkResult => 'error' in result ? { ok: false, reason: result.error.code } : result,(): ChunkResult => ({ ok: false, reason: 'network' }));
    tracker.promise = Promise.race([guard, call]).then(result => {
      clearTimeout(timer); turnSignal.removeEventListener('abort', onAbort!); tracker.settled = true; return result;
    });
    return tracker as { settled: boolean; promise: Promise<ChunkResult> };
  }
  private async play(speech: AdaptedSpeech, generation: number, chunk: number): Promise<boolean> {
    try { this.playback.load({ audioBlob: speech.audio, mouthCues: speech.cues }); } catch { return false; }
    this.playing = true;
    this.publish({ state: 'playing', chunk, reason: null });
    await this.playback.play();
    if (this.stale(generation)) return false;
    const ended = await this.waitForEnd(generation, speech.duration);
    if (this.stale(generation)) return false;
    // clear() revokes the chunk's object URL before the next chunk is loaded.
    this.playing = false; this.playback.clear();
    return ended;
  }
  private waitForEnd(generation: number, duration: number): Promise<boolean> {
    return new Promise(resolve => {
      let done = false, unsubscribe = () => {};
      // Watchdog: media that never reports ended/error is treated as failed rather than stalling the reply.
      const watchdog = setTimeout(() => finish(false), duration * 1000 + this.timeoutMs);
      const finish = (ended: boolean) => { if (done) return; done = true; clearTimeout(watchdog); unsubscribe(); resolve(ended); };
      const check = () => {
        if (this.stale(generation)) return finish(false);
        const state = this.playback.getSnapshot().state;
        if (state === 'ended') finish(true);
        else if (state === 'error' || state === 'stopped' || state === 'disposed') finish(false);
      };
      unsubscribe = this.playback.subscribe(check);
      check();
    });
  }
}
