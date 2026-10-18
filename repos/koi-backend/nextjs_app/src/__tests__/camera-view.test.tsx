import { act, fireEvent, render, screen } from '@testing-library/react';
import CameraView from '../components/camera/CameraView';
import { assertNoVideoLeavesDevice, CAMERA_DISCLOSURE } from '../lib/camera/cameraPrivacyGuard';

class FakeTrack extends EventTarget {
  readonly kind = 'video';
  readyState: 'live' | 'ended' = 'live';
  stop = jest.fn(() => { this.readyState = 'ended'; });
  lose() { this.readyState = 'ended'; this.dispatchEvent(new Event('ended')); }
}
function devices(result: 'ok' | string = 'ok') {
  const tracks: FakeTrack[] = [];
  const getUserMedia = jest.fn(async () => {
    if (result !== 'ok') throw Object.assign(new Error(result), { name: result });
    const track = new FakeTrack(); tracks.push(track);
    return { getTracks: () => [track], getVideoTracks: () => [track], getAudioTracks: () => [] } as unknown as MediaStream;
  });
  return { mediaDevices: { getUserMedia }, getUserMedia, tracks };
}
async function startCamera() {
  await act(async () => { fireEvent.click(screen.getByRole('button', { name: 'Start camera' })); });
}
const video = (container: HTMLElement) => container.querySelector('video') as HTMLVideoElement;

describe('CameraView', () => {
  it('never auto-starts and shows the disclosure verbatim', () => {
    const { getUserMedia, mediaDevices } = devices();
    render(<CameraView ownerUid="u1" mediaDevices={mediaDevices} />);
    expect(getUserMedia).not.toHaveBeenCalled();
    expect(screen.getByText(CAMERA_DISCLOSURE).textContent).toBe('This camera view is for you only. KOI does not record, store, send or analyze your video.');
    expect(screen.queryByText('Camera on')).toBeNull();
  });

  it('starts on click into a muted inline video with the indicator, and turns off in one tap', async () => {
    const { getUserMedia, mediaDevices, tracks } = devices();
    const onStateChange = jest.fn();
    const { container } = render(<CameraView ownerUid="u1" mediaDevices={mediaDevices} onStateChange={onStateChange} />);
    await startCamera();
    expect(getUserMedia).toHaveBeenCalledWith({ video: { facingMode: 'user' }, audio: false });
    expect(screen.getByRole('status')).toHaveTextContent('Camera on');
    const element = video(container);
    expect(element.muted).toBe(true);
    expect(element.hasAttribute('playsinline')).toBe(true);
    expect(element.hidden).toBe(false);
    expect(element.srcObject).not.toBeNull();
    expect(screen.getByText(CAMERA_DISCLOSURE)).toBeInTheDocument();
    act(() => { fireEvent.click(screen.getByRole('button', { name: 'Turn off camera' })); });
    expect(tracks[0].readyState).toBe('ended');
    expect(screen.queryByText('Camera on')).toBeNull();
    expect(element.srcObject).toBeNull();
    expect(onStateChange.mock.calls.map(([state]) => state)).toEqual(['starting', 'on', 'off']);
  });

  it.each([
    ['NotAllowedError', 'Camera permission was denied. Text chat still works.'],
    ['NotFoundError', 'No camera was found on this device. Text chat still works.'],
    ['NotReadableError', 'The camera could not start (it may be in use by another app). Text chat still works.'],
  ])('%s shows a message that says text chat still works', async (error, message) => {
    const { mediaDevices } = devices(error);
    render(<CameraView ownerUid="u1" mediaDevices={mediaDevices} />);
    await startCamera();
    expect(screen.getByRole('alert')).toHaveTextContent(message);
    expect(screen.queryByText('Camera on')).toBeNull();
  });

  it('unsupported browsers get a message that says text chat still works', async () => {
    render(<CameraView ownerUid="u1" mediaDevices={null} />);
    await startCamera();
    expect(screen.getByRole('alert')).toHaveTextContent('This browser cannot show a camera view here. Text chat still works.');
  });

  it('a lost device turns the view off', async () => {
    const { mediaDevices, tracks } = devices();
    render(<CameraView ownerUid="u1" mediaDevices={mediaDevices} />);
    await startCamera();
    act(() => { tracks[0].lose(); });
    expect(screen.queryByText('Camera on')).toBeNull();
    expect(screen.getByRole('button', { name: 'Start camera' })).toBeEnabled();
  });

  it('stops on unmount', async () => {
    const { mediaDevices, tracks } = devices();
    const { unmount } = render(<CameraView ownerUid="u1" mediaDevices={mediaDevices} />);
    await startCamera();
    unmount();
    expect(tracks[0].readyState).toBe('ended');
  });

  it('stops on pagehide', async () => {
    const { mediaDevices, tracks } = devices();
    render(<CameraView ownerUid="u1" mediaDevices={mediaDevices} />);
    await startCamera();
    act(() => { window.dispatchEvent(new Event('pagehide')); });
    expect(tracks[0].readyState).toBe('ended');
    expect(screen.queryByText('Camera on')).toBeNull();
  });

  it('stops when ownerUid changes and does not restart', async () => {
    const { mediaDevices, tracks, getUserMedia } = devices();
    const { rerender } = render(<CameraView ownerUid="u1" mediaDevices={mediaDevices} />);
    await startCamera();
    rerender(<CameraView ownerUid="u2" mediaDevices={mediaDevices} />);
    expect(tracks[0].readyState).toBe('ended');
    expect(screen.queryByText('Camera on')).toBeNull();
    expect(getUserMedia).toHaveBeenCalledTimes(1);
  });

  it('stops when suspended (crisis handoff) and blocks Start; lifting it does not auto-start', async () => {
    const { mediaDevices, tracks, getUserMedia } = devices();
    const { rerender } = render(<CameraView ownerUid="u1" mediaDevices={mediaDevices} />);
    await startCamera();
    rerender(<CameraView ownerUid="u1" mediaDevices={mediaDevices} suspended />);
    expect(tracks[0].readyState).toBe('ended');
    expect(screen.getByRole('button', { name: 'Start camera' })).toBeDisabled();
    rerender(<CameraView ownerUid="u1" mediaDevices={mediaDevices} suspended={false} />);
    expect(getUserMedia).toHaveBeenCalledTimes(1);
    expect(screen.queryByText('Camera on')).toBeNull();
  });

  it('active={false} is an off signal only', async () => {
    const { mediaDevices, tracks, getUserMedia } = devices();
    const { rerender } = render(<CameraView ownerUid="u1" mediaDevices={mediaDevices} active />);
    expect(getUserMedia).not.toHaveBeenCalled();
    await startCamera();
    rerender(<CameraView ownerUid="u1" mediaDevices={mediaDevices} active={false} />);
    expect(tracks[0].readyState).toBe('ended');
    expect(screen.getByRole('button', { name: 'Start camera' })).toBeDisabled();
  });

  it('a stop during the permission prompt releases the late stream', async () => {
    let resolve!: () => void;
    const track = new FakeTrack();
    const getUserMedia = jest.fn(() => new Promise<MediaStream>(r => { resolve = () => r({ getTracks: () => [track], getVideoTracks: () => [track], getAudioTracks: () => [] } as unknown as MediaStream); }));
    const { unmount } = render(<CameraView ownerUid="u1" mediaDevices={{ getUserMedia }} />);
    act(() => { fireEvent.click(screen.getByRole('button', { name: 'Start camera' })); });
    unmount();
    await act(async () => { resolve(); });
    expect(track.readyState).toBe('ended');
  });

  it('never records, captures, sends or stores while on', async () => {
    const spies = { MediaRecorder: jest.fn(), ImageCapture: jest.fn(), OffscreenCanvas: jest.fn(), WebSocket: jest.fn(), fetch: jest.fn() };
    const restore = Object.keys(spies).map(key => [key, Object.getOwnPropertyDescriptor(globalThis, key)] as const);
    Object.assign(globalThis, spies);
    const getContext = jest.spyOn(HTMLCanvasElement.prototype, 'getContext');
    const xhrOpen = jest.spyOn(XMLHttpRequest.prototype, 'open');
    const setItem = jest.spyOn(Storage.prototype, 'setItem');
    const idbOpen = jest.spyOn(indexedDB, 'open');
    try {
      const { mediaDevices } = devices();
      const { container, unmount } = render(<CameraView ownerUid="u1" mediaDevices={mediaDevices} />);
      await startCamera();
      expect(screen.getByText('Camera on')).toBeInTheDocument();
      expect(container.querySelector('canvas')).toBeNull();
      for (const spy of Object.values(spies)) expect(spy).not.toHaveBeenCalled();
      for (const spy of [getContext, xhrOpen, setItem, idbOpen]) expect(spy).not.toHaveBeenCalled();
      assertNoVideoLeavesDevice(spies.fetch.mock.calls);
      unmount();
      expect(localStorage.length).toBe(0);
      expect(sessionStorage.length).toBe(0);
    } finally {
      for (const [key, descriptor] of restore) { if (descriptor) Object.defineProperty(globalThis, key, descriptor); else delete (globalThis as Record<string, unknown>)[key]; }
      jest.restoreAllMocks();
    }
  });
});
