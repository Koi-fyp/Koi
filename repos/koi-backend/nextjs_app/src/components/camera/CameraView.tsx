'use client';
import { useEffect, useRef, useState } from 'react';
import { createCameraSession, type CameraSession, type CameraState } from '../../lib/camera/cameraSession';
import { CAMERA_DISCLOSURE } from '../../lib/camera/cameraPrivacyGuard';

export interface CameraViewProps {
  /** Owner of the view; a different uid turns the camera off. */
  ownerUid: string | null;
  /** Controlled off signal: false turns the camera off and keeps Start disabled. It never turns it on. */
  active?: boolean;
  /** Crisis handoff: true turns the camera off and keeps Start disabled. */
  suspended?: boolean;
  onStateChange?: (state: CameraState) => void;
  /** Injection point for tests; defaults to the browser's mediaDevices. */
  mediaDevices?: Pick<MediaDevices, 'getUserMedia'> | null;
}

const MESSAGES: Partial<Record<CameraState, string>> = {
  denied: 'Camera permission was denied. Text chat still works.',
  'no-device': 'No camera was found on this device. Text chat still works.',
  unsupported: 'This browser cannot show a camera view here. Text chat still works.',
  error: 'The camera could not start (it may be in use by another app). Text chat still works.',
};
const button = { padding: '6px 14px', border: '2px solid #171717', borderRadius: 10, cursor: 'pointer', fontWeight: 700 } as const;

/** Self-view only: the stream goes to a muted local <video> and nowhere else. Never starts on its own. */
export default function CameraView({ ownerUid, active, suspended, onStateChange, mediaDevices }: CameraViewProps) {
  const [state, setState] = useState<CameraState>('off');
  const onStateChangeRef = useRef(onStateChange);
  onStateChangeRef.current = onStateChange;
  const sessionRef = useRef<CameraSession | null>(null);
  const videoRef = useRef<HTMLVideoElement | null>(null);
  if (!sessionRef.current) {
    const devices = mediaDevices !== undefined ? mediaDevices : typeof navigator !== 'undefined' ? navigator.mediaDevices : null;
    sessionRef.current = createCameraSession({ mediaDevices: devices, onChange: next => { setState(next); onStateChangeRef.current?.(next); } });
  }
  const session = sessionRef.current;
  const blocked = suspended === true || active === false;

  // Cleanup runs on unmount and whenever the owner changes.
  useEffect(() => () => session.stop(), [session, ownerUid]);
  useEffect(() => { if (blocked) session.stop(); }, [session, blocked]);
  useEffect(() => {
    const onPageHide = () => session.stop();
    window.addEventListener('pagehide', onPageHide);
    return () => window.removeEventListener('pagehide', onPageHide);
  }, [session]);
  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    video.srcObject = state === 'on' ? session.stream : null;
    return () => { video.srcObject = null; };
  }, [session, state]);

  const on = state === 'on';
  const message = MESSAGES[state];
  return (
    <section aria-label="Camera view" data-camera-state={state} style={{ display: 'grid', gap: 8 }}>
      <p style={{ margin: 0 }} data-camera-disclosure>{CAMERA_DISCLOSURE}</p>
      {on && (
        <p role="status" data-camera-indicator style={{ margin: 0, fontWeight: 700, display: 'flex', alignItems: 'center', gap: 6 }}>
          <span aria-hidden="true" style={{ width: 10, height: 10, borderRadius: '50%', background: '#d92d20', display: 'inline-block' }} />
          Camera on
        </p>
      )}
      <video ref={videoRef} muted playsInline autoPlay hidden={!on} aria-label="Your camera preview"
        style={{ width: '100%', maxWidth: 480, borderRadius: 12, transform: 'scaleX(-1)', background: '#000' }} />
      {on
        ? <button type="button" onClick={() => session.stop()} style={{ ...button, background: '#fff' }}>Turn off camera</button>
        : <button type="button" disabled={blocked || state === 'starting'} onClick={() => { void session.start(); }}
            style={{ ...button, background: 'var(--neo-yellow, #ffd100)' }}>{state === 'starting' ? 'Starting camera…' : 'Start camera'}</button>}
      {message && <p role="alert" style={{ margin: 0 }}>{message}</p>}
    </section>
  );
}
