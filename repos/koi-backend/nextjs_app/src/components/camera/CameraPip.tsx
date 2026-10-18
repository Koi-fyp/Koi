'use client';
import { useEffect, useRef, useState, type CSSProperties } from 'react';
import { createCameraSession, type CameraSession, type CameraState } from '../../lib/camera/cameraSession';
import { CAMERA_DISCLOSURE } from '../../lib/camera/cameraPrivacyGuard';

export interface CameraPipProps {
  /** A video mode is selected: the camera opens; turning it off releases the device. */
  enabled: boolean;
  /** Crisis handoff: the camera closes and stays closed while true. */
  suspended?: boolean;
  /** A different signed-in user turns the camera off. */
  ownerUid: string | null;
  /** Closes the view (the parent sets enabled=false, which releases the camera). */
  onClose?: () => void;
  style?: CSSProperties;
  mediaDevices?: Pick<MediaDevices, 'getUserMedia'> | null;
}

const MESSAGES: Partial<Record<CameraState, string>> = {
  starting: 'Opening camera…',
  denied: 'Camera permission was denied.',
  'no-device': 'No camera found.',
  unsupported: 'Camera not supported here.',
  error: 'Camera could not start (in use by another app?).',
  off: 'Camera off',
};
const small = { fontSize: 11, padding: '3px 10px', border: '2px solid #000', borderRadius: 999, background: '#fff', color: '#000', cursor: 'pointer', fontWeight: 700, flexShrink: 0 } as const;

/** Picture-in-picture self-view. The stream goes to a muted local <video> only: never recorded, uploaded or analysed. */
export default function CameraPip({ enabled, suspended = false, ownerUid, onClose, style, mediaDevices }: CameraPipProps) {
  const [state, setState] = useState<CameraState>('off');
  const sessionRef = useRef<CameraSession | null>(null);
  const videoRef = useRef<HTMLVideoElement | null>(null);
  if (!sessionRef.current) {
    const devices = mediaDevices !== undefined ? mediaDevices : typeof navigator !== 'undefined' ? navigator.mediaDevices : null;
    sessionRef.current = createCameraSession({ mediaDevices: devices, onChange: setState });
  }
  const session = sessionRef.current;
  const allowed = enabled && !suspended;
  useEffect(() => {
    if (allowed) void session.start(); else session.stop();
    return () => session.stop();
  }, [session, allowed, ownerUid]);
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
  if (!enabled) return null;
  const on = state === 'on';
  return <section aria-label="Your camera" data-camera-state={state} title={CAMERA_DISCLOSURE}
    style={{ display: 'grid', gap: 6, padding: 6, background: '#111', border: '3px solid #000', borderRadius: 16, boxShadow: '4px 4px 0 #000', color: '#fff', ...style }}>
    <video ref={videoRef} muted playsInline autoPlay hidden={!on} aria-label="Your camera preview"
      style={{ width: '100%', aspectRatio: '4 / 3', objectFit: 'cover', borderRadius: 10, transform: 'scaleX(-1)', background: '#000' }} />
    {!on && <p role={state === 'off' || state === 'starting' ? 'status' : 'alert'} style={{ margin: 0, padding: '18px 6px', fontSize: 12, textAlign: 'center' }}>
      {suspended ? 'Camera paused' : MESSAGES[state]}</p>}
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 6, fontSize: 10 }}>
      <span style={{ lineHeight: 1.3 }}>{on ? <><span aria-hidden="true" style={{ color: '#ff4a4a' }}>●</span> Only you see this</> : 'Stays on this device'}</span>
      {!on && !suspended && state !== 'starting' && state !== 'off' && <button type="button" style={small} onClick={() => { void session.start(); }}>Retry</button>}
      <button type="button" style={small} onClick={() => { session.stop(); onClose?.(); }} aria-label="Turn off camera">Turn off</button>
    </div>
  </section>;
}
