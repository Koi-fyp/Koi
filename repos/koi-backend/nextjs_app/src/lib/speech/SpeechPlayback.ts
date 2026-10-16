import { parseMouthCues, type MouthCue, type SpeechFrame, type SpeechTimeline } from './mouthCues';
export type PlaybackState = 'idle' | 'loading' | 'playing' | 'paused' | 'ended' | 'stopped' | 'error' | 'disposed';
export type SpeechSource = ({ audioUrl: string; audioBlob?: never } | { audioBlob: Blob; audioUrl?: never }) & { mouthCues: readonly MouthCue[] };
export interface PlaybackSnapshot { state: PlaybackState; time: number; duration: number; error: string | null; }
/** One local audio element; no timers/RAF, recording, backend choice or conversation ownership. */
export class SpeechPlayback implements SpeechTimeline {
  private audio: HTMLAudioElement;
  private ownedUrl?: string;
  private cues: readonly MouthCue[] = [];
  private version = 0; private disposed = false;
  private snapshot: PlaybackSnapshot = { state: 'idle', time: 0, duration: 0, error: null };
  private listeners = new Set<() => void>();
  private readonly events = ['playing', 'pause', 'ended', 'error', 'timeupdate', 'loadedmetadata', 'seeking', 'seeked', 'waiting'] as const;
  constructor(createAudio: () => HTMLAudioElement = () => new Audio()) {
    this.audio = createAudio(); this.audio.preload = 'metadata';
    for (const event of this.events) this.audio.addEventListener(event, this.onMedia);
  }
  getSnapshot = () => this.snapshot;
  subscribe = (listener: () => void) => { this.listeners.add(listener); return () => { this.listeners.delete(listener); }; };
  private publish(state = this.snapshot.state, error: string | null = null) {
    if (this.disposed) return;
    this.snapshot = { state, error, time: Number.isFinite(this.audio.currentTime) ? this.audio.currentTime : 0, duration: Number.isFinite(this.audio.duration) ? this.audio.duration : 0 };
    this.listeners.forEach((listener) => listener());
  }
  private onMedia = (event: Event) => {
    if (this.disposed) return;
    if (event.type === 'error') { this.version++; this.audio.pause(); this.publish('error', 'The local speech audio could not be loaded.'); }
    else if (event.type === 'ended') { if (this.audio.ended) this.publish('ended'); }
    else if (event.type === 'playing') { if (!this.audio.paused && !this.audio.ended) this.publish('playing'); }
    else if (event.type === 'pause' && this.audio.paused && !['stopped', 'error', 'idle', 'ended'].includes(this.snapshot.state)) this.publish(this.audio.ended ? 'ended' : 'paused');
    else if (event.type === 'waiting') { if (!this.audio.paused) this.publish('loading'); }
    else this.publish();
  };
  load(source: SpeechSource) {
    if (this.disposed) return;
    const cues = parseMouthCues(source.mouthCues);
    const url = source.audioUrl !== undefined ? new URL(source.audioUrl, window.location.href) : undefined;
    if (source.audioBlob && (source.audioBlob.type !== 'audio/wav' || !source.audioBlob.size || source.audioBlob.size > 2 * 1024 * 1024)) throw new Error('Invalid owned speech audio.');
    // No unapproved transmission. Future remote TTS needs an explicit origin/privacy decision.
    if (url && (url.origin !== window.location.origin || !['http:', 'https:'].includes(url.protocol))) throw new Error('Speech audio must use the application origin.');
    this.clear(); this.cues = cues;
    if (source.audioBlob) this.ownedUrl = URL.createObjectURL(source.audioBlob);
    this.audio.src = this.ownedUrl ?? url!.href; this.audio.load(); this.publish('idle');
  }
  async play() {
    if (this.disposed || !this.audio.src || this.snapshot.state === 'playing' || this.snapshot.state === 'loading') return;
    const version = ++this.version;
    if (this.audio.ended) this.audio.currentTime = 0;
    this.publish('loading');
    try { await this.audio.play(); if (version === this.version && !this.disposed) this.publish('playing'); }
    catch { if (version === this.version && !this.disposed) this.publish('error', 'Playback was unavailable. Click Play to try again.'); }
  }
  pause() { if (this.disposed) return; this.version++; this.audio.pause(); this.publish('paused'); }
  stop() { if (this.disposed) return; this.version++; this.audio.pause(); this.audio.currentTime = 0; this.publish('stopped'); }
  clear() { if (this.disposed) return; this.stop(); this.audio.removeAttribute('src'); this.audio.load(); if (this.ownedUrl) URL.revokeObjectURL(this.ownedUrl); this.ownedUrl = undefined; this.cues = []; }
  seek(seconds: number) {
    if (this.disposed || !Number.isFinite(seconds) || !Number.isFinite(this.audio.duration)) return;
    this.audio.currentTime = Math.min(this.audio.duration, Math.max(0, seconds)); this.publish();
  }
  getFrame(): SpeechFrame {
    return { active: !this.disposed && this.snapshot.state === 'playing' && !this.audio.paused && !this.audio.ended && !this.audio.seeking,
      time: this.audio.currentTime, cues: this.cues };
  }
  dispose() {
    if (this.disposed) return;
    this.clear(); this.disposed = true;
    for (const event of this.events) this.audio.removeEventListener(event, this.onMedia);
    this.audio.removeAttribute('src'); this.audio.load(); this.cues = [];
    this.snapshot = { state: 'disposed', time: 0, duration: 0, error: null }; this.listeners.clear();
  }
}
