export type CameraState = 'off' | 'starting' | 'on' | 'denied' | 'no-device' | 'unsupported' | 'error';
/** 'cancelled': stop() (or a newer start) won the race against a pending permission prompt. */
export type CameraStartResult = 'on' | 'denied' | 'no-device' | 'unsupported' | 'error' | 'cancelled';
export interface CameraSession {
  readonly state: CameraState;
  /** Only for attaching to a local <video>. Never read frames from it. */
  readonly stream: MediaStream | null;
  start(): Promise<CameraStartResult>;
  stop(): void;
}
export interface CameraSessionOptions {
  mediaDevices?: Pick<MediaDevices, 'getUserMedia'> | null;
  onChange?: (state: CameraState) => void;
}
// The only constraint ever sent: front camera, never a microphone.
export const CAMERA_CONSTRAINTS: Readonly<MediaStreamConstraints> = Object.freeze({ video: Object.freeze({ facingMode: 'user' }), audio: false });

function classify(error: unknown): Exclude<CameraStartResult, 'on' | 'cancelled'> {
  const name = (error as { name?: unknown } | null)?.name;
  if (name === 'NotAllowedError' || name === 'SecurityError' || name === 'PermissionDeniedError') return 'denied';
  if (name === 'NotFoundError' || name === 'DevicesNotFoundError' || name === 'OverconstrainedError') return 'no-device';
  return 'error';
}

/**
 * Local view only: the stream exists to be shown in a <video> on this device and is released on stop().
 * Nothing here captures, encodes, persists or transmits frames, and nothing starts without an explicit start().
 */
export function createCameraSession({ mediaDevices, onChange }: CameraSessionOptions = {}): CameraSession {
  let state: CameraState = 'off';
  let stream: MediaStream | null = null;
  let token = 0;
  const set = (next: CameraState) => { if (next === state) return; state = next; onChange?.(next); };
  const release = () => {
    const current = stream; stream = null;
    for (const track of current?.getTracks() ?? []) { track.removeEventListener('ended', onEnded); track.stop(); }
  };
  // Device unplugged or revoked by the OS/browser: release everything and report off.
  const onEnded = () => { token++; release(); set('off'); };

  async function start(): Promise<CameraStartResult> {
    if (state === 'on') return 'on';
    if (!mediaDevices || typeof mediaDevices.getUserMedia !== 'function') { set('unsupported'); return 'unsupported'; }
    const mine = ++token;
    release(); set('starting');
    let next: MediaStream;
    try { next = await mediaDevices.getUserMedia(CAMERA_CONSTRAINTS); }
    catch (error) {
      if (mine !== token) return 'cancelled';
      const result = classify(error); set(result); return result;
    }
    if (mine !== token) { for (const track of next.getTracks()) track.stop(); return 'cancelled'; }
    // Defensive: a microphone track must never survive, even if a browser ignores audio:false.
    for (const track of next.getAudioTracks()) track.stop();
    const video = next.getVideoTracks().filter(track => track.readyState !== 'ended');
    if (!video.length) { for (const track of next.getTracks()) track.stop(); set('no-device'); return 'no-device'; }
    stream = next;
    for (const track of video) track.addEventListener('ended', onEnded);
    set('on');
    return 'on';
  }

  function stop() { token++; release(); set('off'); }

  return {
    get state() { return state; },
    get stream() { return stream; },
    start, stop,
  };
}
