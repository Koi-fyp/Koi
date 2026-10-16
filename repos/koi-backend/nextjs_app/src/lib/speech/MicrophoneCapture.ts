export type CaptureState = 'idle' | 'requesting' | 'recording' | 'stopping' | 'ready' | 'error' | 'disposed';
export type MicrophonePermission = 'unknown' | 'prompt' | 'granted' | 'denied' | 'unsupported';
export interface CaptureInput { deviceId: string; label: string; }
export interface CaptureSnapshot {
 state: CaptureState; blob: Blob | null; mimeType: string; error: string | null;
 permission: MicrophonePermission; inputs: CaptureInput[]; durationMs: number; bytes: number;
 input: { label: string; sampleRate?: number; channelCount?: number; state: MediaStreamTrackState } | null;
}
export const MAX_RECORDING_MS = 29500, MAX_RECORDING_BYTES = 2 * 1024 * 1024;
export class MicrophoneCapture {
 private snapshot: CaptureSnapshot = { state: 'idle', blob: null, mimeType: '', error: null, permission: 'unknown', inputs: [], durationMs: 0, bytes: 0, input: null };
 private listeners = new Set<() => void>(); private version = 0; private disposed = false;
 private stream?: MediaStream; private recorder?: MediaRecorder; private chunks: Blob[] = []; private bytes = 0; private startedAt = 0; private timer?: ReturnType<typeof setTimeout>;
 getSnapshot = () => this.snapshot;
 subscribe = (listener: () => void) => { this.listeners.add(listener); return () => { this.listeners.delete(listener); }; };
 private publish(update: Partial<CaptureSnapshot>) { if (this.disposed) return; this.snapshot = { ...this.snapshot, ...update }; this.listeners.forEach(listener => listener()); }
 private hidden = (event: Event) => { if (event.type === 'pagehide' || (typeof document !== 'undefined' && document.visibilityState === 'hidden')) this.cancel(); };
 private disconnected = () => this.fail('The microphone disconnected. The recording was discarded.');
 private release() {
  if (typeof document !== 'undefined') document.removeEventListener('visibilitychange', this.hidden);
  if (typeof window !== 'undefined') window.removeEventListener?.('pagehide', this.hidden);
  clearTimeout(this.timer); this.timer = undefined;
  if (this.recorder) { this.recorder.onstop = this.recorder.ondataavailable = this.recorder.onerror = null; if (this.recorder.state !== 'inactive') this.recorder.stop(); this.recorder = undefined; }
  this.stream?.getTracks().forEach(track => { track.removeEventListener('ended', this.disconnected); track.stop(); }); this.stream = undefined; this.chunks = [];
 }
 private fail(message: string) { this.version++; const input = this.snapshot.input ? { ...this.snapshot.input, state: 'ended' as const } : null; this.release(); this.publish({ state: 'error', blob: null, error: message, bytes: this.bytes, input, durationMs: this.startedAt ? Math.max(0, Date.now() - this.startedAt) : 0 }); }
 async refreshInputs() {
  try {
   const permission = await navigator.permissions?.query({ name: 'microphone' as PermissionName });
   const devices = await navigator.mediaDevices?.enumerateDevices();
   this.publish({ permission: permission?.state ?? this.snapshot.permission, inputs: (devices ?? []).filter(device => device.kind === 'audioinput').map((device, index) => ({ deviceId: device.deviceId, label: device.label || `Microphone ${index + 1}` })) });
  } catch { /* Enumeration and Permissions API support vary by browser. */ }
 }
 /** Call only from the user's explicit consent/record button. Never invoked on mount. */
 async start(deviceId?: string) {
  if (this.disposed || ['requesting', 'recording', 'stopping'].includes(this.snapshot.state)) return;
  this.cancel(); const version = ++this.version; this.bytes = 0; this.startedAt = 0; this.publish({ state: 'requesting', blob: null, error: null, bytes: 0, durationMs: 0, input: null });
  if (typeof document !== 'undefined') document.addEventListener('visibilitychange', this.hidden);
  window.addEventListener?.('pagehide', this.hidden);
  try {
   if (!globalThis.isSecureContext) throw new Error('insecure-context');
   if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder === 'undefined') throw new Error('unsupported');
   const constraints: MediaStreamConstraints = { audio: deviceId ? { deviceId: { exact: deviceId } } : true, video: false };
   const stream = await navigator.mediaDevices.getUserMedia(constraints);
   if (version !== this.version || this.disposed) { stream.getTracks().forEach(track => track.stop()); return; }
   this.stream = stream;
   if (!stream.getAudioTracks().some(track => track.readyState === 'live')) throw new Error('missing');
   const track = stream.getAudioTracks()[0], settings = track.getSettings();
   this.publish({ permission: 'granted', input: { label: track.label || this.snapshot.inputs.find(input => input.deviceId === deviceId)?.label || 'Selected microphone', sampleRate: settings.sampleRate, channelCount: settings.channelCount, state: track.readyState } });
   const mimeType = ['audio/webm;codecs=opus', 'audio/ogg;codecs=opus', 'audio/mp4'].find(type => MediaRecorder.isTypeSupported(type));
   if (!mimeType) throw new Error('format');
   const recorder = this.recorder = new MediaRecorder(stream, { mimeType });
   stream.getTracks().forEach(track => track.addEventListener('ended', this.disconnected));
   recorder.ondataavailable = event => {
    if (version !== this.version || this.disposed) return;
    this.bytes += event.data.size;
    if (this.bytes > MAX_RECORDING_BYTES) { this.fail('Recording exceeded 2 MiB and was discarded.'); return; }
    if (event.data.size) this.chunks.push(event.data);
     this.publish({ bytes: this.bytes, durationMs: this.startedAt ? Math.max(0, Date.now() - this.startedAt) : 0 });
   };
   recorder.onerror = () => this.fail('Audio capture failed. The recording was discarded.');
   recorder.onstop = () => {
    if (version !== this.version || this.disposed) return;
    const type = recorder.mimeType || mimeType, blob = new Blob(this.chunks, { type }), durationMs = Math.max(0, Date.now() - this.startedAt), bytes = this.bytes, input = this.snapshot.input ? { ...this.snapshot.input, state: 'ended' as const } : null; this.release();
    if (!blob.size) { this.fail('No audio was recorded.'); return; }
    this.publish({ state: 'ready', blob, mimeType: type, bytes, durationMs, input, permission: 'granted' });
   };
   recorder.start(250); this.startedAt = Date.now(); this.publish({ state: 'recording', mimeType: recorder.mimeType || mimeType });
   this.timer = setTimeout(() => this.stop(), MAX_RECORDING_MS);
  } catch (error) {
   if (version !== this.version || this.disposed) return;
   const name = error instanceof Error ? error.name : '';
   if (name === 'NotAllowedError' || name === 'PermissionDeniedError') this.publish({ permission: 'denied' });
   this.fail(error instanceof Error && error.message === 'insecure-context' ? 'Microphone access requires localhost or HTTPS.' : name === 'NotAllowedError' || name === 'PermissionDeniedError' ? 'Microphone permission was denied.' : name === 'NotFoundError' ? 'No microphone was found.' : name === 'NotReadableError' ? 'The microphone is busy or could not be opened. Close other apps using it and retry.' : name === 'OverconstrainedError' ? 'The selected microphone is unavailable. Choose another input and retry.' : 'The microphone or recording format is unavailable.');
  }
 }
 stop() { if (this.disposed || this.recorder?.state !== 'recording') return; clearTimeout(this.timer); this.publish({ state: 'stopping', durationMs: this.startedAt ? Math.max(0, Date.now() - this.startedAt) : 0 }); this.recorder.stop(); }
 cancel() { if (this.disposed) return; this.version++; this.release(); this.bytes = 0; this.startedAt = 0; this.publish({ state: 'idle', blob: null, error: null, mimeType: '', bytes: 0, durationMs: 0, input: null }); }
 dispose() { if (this.disposed) return; this.cancel(); this.disposed = true; this.snapshot = { state: 'disposed', blob: null, mimeType: '', error: null, permission: 'unknown', inputs: [], durationMs: 0, bytes: 0, input: null }; this.listeners.clear(); }
}
