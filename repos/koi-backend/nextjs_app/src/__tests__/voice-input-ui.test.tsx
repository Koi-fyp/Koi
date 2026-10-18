/** @jest-environment jsdom */
import React from 'react';
import { act, fireEvent, render, screen } from '@testing-library/react';
import MicButton from '@/components/voice/MicButton';
import type { CaptureSnapshot, MicrophoneCapture } from '@/lib/speech/MicrophoneCapture';
import CameraPip from '@/components/camera/CameraPip';

function fakeCapture() {
  let snapshot: CaptureSnapshot = { state: 'idle', blob: null, mimeType: '', error: null, permission: 'unknown', inputs: [], durationMs: 0, bytes: 0, input: null };
  const listeners = new Set<() => void>();
  const set = (update: Partial<CaptureSnapshot>) => { snapshot = { ...snapshot, ...update }; listeners.forEach(listener => listener()); };
  const capture = {
    getSnapshot: () => snapshot,
    subscribe: (listener: () => void) => { listeners.add(listener); return () => { listeners.delete(listener); }; },
    start: jest.fn(async () => set({ state: 'recording', durationMs: 3200 })),
    stop: jest.fn(() => set({ state: 'ready', blob: new Blob([new Uint8Array(6)], { type: 'audio/webm' }) })),
    cancel: jest.fn(() => set({ state: 'idle', blob: null })),
    dispose: jest.fn(),
    fail: (error: string) => set({ state: 'error', error }),
  };
  return capture;
}

describe('MicButton', () => {
  it('records on tap, sends exactly once on the second tap, and can be discarded', async () => {
    const capture = fakeCapture(); const onRecorded = jest.fn();
    render(<MicButton onRecorded={onRecorded} createCapture={() => capture as unknown as MicrophoneCapture} />);
    expect(capture.start).not.toHaveBeenCalled(); // never on mount
    await act(async () => { fireEvent.click(screen.getByRole('button', { name: 'Start voice message' })); });
    expect(screen.getByRole('button', { name: 'Stop and send voice message' })).toHaveAttribute('aria-pressed', 'true');
    expect(screen.getByText(/Recording 0:03/)).toBeInTheDocument();
    act(() => { fireEvent.click(screen.getByRole('button', { name: 'Stop and send voice message' })); });
    expect(onRecorded).toHaveBeenCalledTimes(1);
    expect((onRecorded.mock.calls[0][0] as Blob).size).toBe(6);
    expect(capture.cancel).toHaveBeenCalled(); // the hook drops its copy after handing it over
    await act(async () => { fireEvent.click(screen.getByRole('button', { name: 'Start voice message' })); });
    act(() => { fireEvent.click(screen.getByRole('button', { name: 'Discard' })); });
    expect(onRecorded).toHaveBeenCalledTimes(1);
  });

  it('shows permission errors and is disabled while a reply is pending', async () => {
    const capture = fakeCapture();
    const { rerender } = render(<MicButton onRecorded={jest.fn()} disabled createCapture={() => capture as unknown as MicrophoneCapture} />);
    expect(screen.getByRole('button', { name: 'Start voice message' })).toBeDisabled();
    rerender(<MicButton onRecorded={jest.fn()} createCapture={() => capture as unknown as MicrophoneCapture} />);
    act(() => capture.fail('Microphone permission was denied.'));
    expect(screen.getByRole('alert')).toHaveTextContent('Microphone permission was denied.');
  });
});

describe('CameraPip', () => {
  function devices() {
    const track = { kind: 'video', readyState: 'live', stop: jest.fn(), addEventListener: jest.fn(), removeEventListener: jest.fn() };
    const stream = { getTracks: () => [track], getVideoTracks: () => [track], getAudioTracks: () => [] } as unknown as MediaStream;
    return { track, mediaDevices: { getUserMedia: jest.fn(async () => stream) } };
  }
  beforeAll(() => { Object.defineProperty(HTMLMediaElement.prototype, 'srcObject', { configurable: true, set() {}, get() { return null; } }); });

  it('opens a video-only self-view when enabled and releases it on close', async () => {
    const { track, mediaDevices } = devices(); const onClose = jest.fn();
    const { rerender } = render(<CameraPip enabled ownerUid="u1" mediaDevices={mediaDevices} onClose={onClose} />);
    await act(async () => {});
    expect(mediaDevices.getUserMedia).toHaveBeenCalledWith({ video: { facingMode: 'user' }, audio: false });
    expect(screen.getByText(/Only you see this/)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Turn off camera' }));
    expect(track.stop).toHaveBeenCalled();
    expect(onClose).toHaveBeenCalled();
    rerender(<CameraPip enabled={false} ownerUid="u1" mediaDevices={mediaDevices} />);
    expect(screen.queryByRole('region', { name: 'Your camera' })).toBeNull();
  });

  it('pauses during a crisis handoff', async () => {
    const { track, mediaDevices } = devices();
    const { rerender } = render(<CameraPip enabled ownerUid="u1" mediaDevices={mediaDevices} />);
    await act(async () => {});
    rerender(<CameraPip enabled suspended ownerUid="u1" mediaDevices={mediaDevices} />);
    expect(track.stop).toHaveBeenCalled();
    expect(screen.getByText('Camera paused')).toBeInTheDocument();
  });
});
