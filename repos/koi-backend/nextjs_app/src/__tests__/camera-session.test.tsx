import fs from 'fs';
import path from 'path';
import { createCameraSession, CAMERA_CONSTRAINTS } from '../lib/camera/cameraSession';
import { assertNoVideoLeavesDevice, CAMERA_DISCLOSURE } from '../lib/camera/cameraPrivacyGuard';

class FakeTrack extends EventTarget {
  readyState: 'live' | 'ended' = 'live';
  stop = jest.fn(() => { this.readyState = 'ended'; });
  constructor(readonly kind: 'video' | 'audio') { super(); }
  lose() { this.readyState = 'ended'; this.dispatchEvent(new Event('ended')); }
}
function fakeStream(...tracks: FakeTrack[]) {
  return {
    getTracks: () => [...tracks],
    getVideoTracks: () => tracks.filter(track => track.kind === 'video'),
    getAudioTracks: () => tracks.filter(track => track.kind === 'audio'),
  } as unknown as MediaStream;
}
const named = (name: string) => Object.assign(new Error(name), { name });

describe('createCameraSession', () => {
  it('never calls getUserMedia before start(), and always sends video-only constraints', async () => {
    const track = new FakeTrack('video');
    const getUserMedia = jest.fn().mockResolvedValue(fakeStream(track));
    const session = createCameraSession({ mediaDevices: { getUserMedia } });
    expect(getUserMedia).not.toHaveBeenCalled();
    expect(session.state).toBe('off');
    await expect(session.start()).resolves.toBe('on');
    expect(getUserMedia).toHaveBeenCalledTimes(1);
    expect(getUserMedia).toHaveBeenCalledWith({ video: { facingMode: 'user' }, audio: false });
    expect(CAMERA_CONSTRAINTS.audio).toBe(false);
  });

  it('start/stop releases every track and notifies each state', async () => {
    const tracks = [new FakeTrack('video'), new FakeTrack('video')];
    const onChange = jest.fn();
    const session = createCameraSession({ mediaDevices: { getUserMedia: jest.fn().mockResolvedValue(fakeStream(...tracks)) }, onChange });
    await session.start();
    expect(session.state).toBe('on');
    expect(session.stream).not.toBeNull();
    session.stop();
    expect(session.state).toBe('off');
    expect(session.stream).toBeNull();
    for (const track of tracks) { expect(track.stop).toHaveBeenCalled(); expect(track.readyState).toBe('ended'); }
    expect(onChange.mock.calls.map(([state]) => state)).toEqual(['starting', 'on', 'off']);
  });

  it('stops a microphone track if a browser returns one anyway', async () => {
    const video = new FakeTrack('video'), audio = new FakeTrack('audio');
    const session = createCameraSession({ mediaDevices: { getUserMedia: jest.fn().mockResolvedValue(fakeStream(video, audio)) } });
    await session.start();
    expect(audio.readyState).toBe('ended');
    expect(video.readyState).toBe('live');
    session.stop();
    expect(video.readyState).toBe('ended');
  });

  it.each([
    ['NotAllowedError', 'denied'], ['SecurityError', 'denied'],
    ['NotFoundError', 'no-device'], ['OverconstrainedError', 'no-device'],
    ['NotReadableError', 'error'], ['AbortError', 'error'],
  ])('maps %s to %s', async (name, expected) => {
    const session = createCameraSession({ mediaDevices: { getUserMedia: jest.fn().mockRejectedValue(named(name)) } });
    await expect(session.start()).resolves.toBe(expected);
    expect(session.state).toBe(expected);
    expect(session.stream).toBeNull();
  });

  it('reports no-device when the stream has no live video track', async () => {
    const dead = new FakeTrack('video'); dead.readyState = 'ended';
    const session = createCameraSession({ mediaDevices: { getUserMedia: jest.fn().mockResolvedValue(fakeStream(dead)) } });
    await expect(session.start()).resolves.toBe('no-device');
  });

  it.each([[undefined], [null], [{}]])('reports unsupported without mediaDevices.getUserMedia (%p)', async (mediaDevices) => {
    const session = createCameraSession({ mediaDevices: mediaDevices as never });
    await expect(session.start()).resolves.toBe('unsupported');
    expect(session.state).toBe('unsupported');
  });

  it('moves to off and notifies when the device is lost (track ended)', async () => {
    const lost = new FakeTrack('video'), other = new FakeTrack('video');
    const onChange = jest.fn();
    const session = createCameraSession({ mediaDevices: { getUserMedia: jest.fn().mockResolvedValue(fakeStream(lost, other)) }, onChange });
    await session.start();
    onChange.mockClear();
    lost.lose();
    expect(session.state).toBe('off');
    expect(session.stream).toBeNull();
    expect(other.readyState).toBe('ended');
    expect(onChange).toHaveBeenCalledWith('off');
  });

  it('stop() during a pending permission prompt releases the late stream', async () => {
    const track = new FakeTrack('video');
    let resolve!: (stream: MediaStream) => void;
    const session = createCameraSession({ mediaDevices: { getUserMedia: jest.fn(() => new Promise<MediaStream>(r => { resolve = r; })) } });
    const pending = session.start();
    expect(session.state).toBe('starting');
    session.stop();
    resolve(fakeStream(track));
    await expect(pending).resolves.toBe('cancelled');
    expect(session.state).toBe('off');
    expect(track.readyState).toBe('ended');
    expect(session.stream).toBeNull();
  });

  it('start() while on is a no-op', async () => {
    const getUserMedia = jest.fn().mockResolvedValue(fakeStream(new FakeTrack('video')));
    const session = createCameraSession({ mediaDevices: { getUserMedia } });
    await session.start();
    await expect(session.start()).resolves.toBe('on');
    expect(getUserMedia).toHaveBeenCalledTimes(1);
  });

  it('never touches capture, encoding, network or storage APIs while on', async () => {
    const spies = {
      MediaRecorder: jest.fn(), ImageCapture: jest.fn(), OffscreenCanvas: jest.fn(), WebSocket: jest.fn(), fetch: jest.fn(),
    };
    const restore = Object.keys(spies).map(key => [key, Object.getOwnPropertyDescriptor(globalThis, key)] as const);
    Object.assign(globalThis, spies);
    const getContext = jest.spyOn(HTMLCanvasElement.prototype, 'getContext');
    const createElement = jest.spyOn(document, 'createElement');
    const xhrOpen = jest.spyOn(XMLHttpRequest.prototype, 'open');
    const setItem = jest.spyOn(Storage.prototype, 'setItem');
    const idbOpen = jest.spyOn(indexedDB, 'open');
    try {
      const session = createCameraSession({ mediaDevices: { getUserMedia: jest.fn().mockResolvedValue(fakeStream(new FakeTrack('video'))) } });
      await session.start();
      expect(session.state).toBe('on');
      session.stop();
      for (const spy of Object.values(spies)) expect(spy).not.toHaveBeenCalled();
      for (const spy of [getContext, createElement, xhrOpen, setItem, idbOpen]) expect(spy).not.toHaveBeenCalled();
      expect(localStorage.length).toBe(0);
    } finally {
      for (const [key, descriptor] of restore) { if (descriptor) Object.defineProperty(globalThis, key, descriptor); else delete (globalThis as Record<string, unknown>)[key]; }
      jest.restoreAllMocks();
    }
  });

  it('camera sources contain no capture, network or storage API references', () => {
    const forbidden = /MediaRecorder|ImageCapture|OffscreenCanvas|getContext|captureStream|requestVideoFrameCallback|drawImage|toDataURL|toBlob|createElement|fetch\s*\(|XMLHttpRequest|WebSocket|sendBeacon|indexedDB|localStorage|sessionStorage|audio:\s*true/;
    for (const file of ['lib/camera/cameraSession.ts', 'components/camera/CameraView.tsx']) {
      expect(fs.readFileSync(path.join(__dirname, '..', file), 'utf8')).not.toMatch(forbidden);
    }
  });
});

describe('cameraPrivacyGuard', () => {
  it('exports the disclosure verbatim', () => {
    expect(CAMERA_DISCLOSURE).toBe('This camera view is for you only. KOI does not record, store, send or analyze your video.');
  });

  it('accepts no calls and plain JSON text calls', () => {
    expect(() => assertNoVideoLeavesDevice([])).not.toThrow();
    expect(() => assertNoVideoLeavesDevice([['/api/chat', { method: 'POST', body: '{"text":"hi"}', headers: { 'Content-Type': 'application/json' } }], ['/x']])).not.toThrow();
  });

  it.each([
    ['video blob', { body: new Blob(['x'], { type: 'video/webm' }) }],
    ['image blob', { body: new Blob(['x'], { type: 'image/jpeg' }) }],
    ['binary body', { body: new Uint8Array([1, 2, 3]) }],
    ['data URL', { body: JSON.stringify({ frame: 'data:image/png;base64,AAAA' }) }],
    ['multipart file', { body: (() => { const form = new FormData(); form.append('video', new Blob(['x'], { type: 'video/webm' })); return form; })() }],
    ['video content type', { body: 'x', headers: { 'content-type': 'video/mp4' } }],
  ])('rejects a %s', (_label, init) => {
    expect(() => assertNoVideoLeavesDevice([['/upload', init]])).toThrow(/Camera privacy violation/);
  });
});
