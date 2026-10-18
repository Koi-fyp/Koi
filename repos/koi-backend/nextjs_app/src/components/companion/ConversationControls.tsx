import type { ReactNode, RefObject } from 'react';
import NeoButton from '@/components/ui/NeoButton';
import CallIcon from './CallIcon';
import styles from './CompanionScene.module.css';
export default function ConversationControls({ textOpen, onToggleText, onEnd, toggleRef, textLocked = false, voiceControl, micControl, cameraControl }: {
  textOpen: boolean; onToggleText: () => void; onEnd: () => void; toggleRef: RefObject<HTMLButtonElement>; textLocked?: boolean; voiceControl?: ReactNode;
  /** A working mic control (button + status). Without one the mic shows as off for the current mode. */
  micControl?: ReactNode;
  /** A working camera toggle. Without one the camera shows as off for the current mode. */
  cameraControl?: ReactNode;
}) {
  return <footer className={styles.footer}>
    <div className={styles.controls} aria-label="Conversation controls">
      <div className={styles.control}>{micControl ?? <><NeoButton type="button" className={styles.callButton} disabled aria-label="Microphone off" title="Choose Audio or Video + Audio in Mode to talk"><CallIcon name="microphone" /></NeoButton><span>Mic: pick Audio mode</span></>}</div>
      <div className={styles.control}>{cameraControl ?? <><NeoButton type="button" className={styles.callButton} disabled aria-label="Camera off" title="Choose a Video mode to see yourself"><CallIcon name="camera" /></NeoButton><span>Camera: pick Video mode</span></>}</div>
      <div className={styles.control}><button ref={toggleRef} type="button" disabled={textLocked} className={`${styles.callButton} ${textOpen ? styles.active : ''}`} onClick={onToggleText} aria-label="Text conversation" aria-expanded={textOpen} aria-controls="conversation-text"><CallIcon name="text" /></button><span>{textLocked ? 'Text only' : textOpen ? 'Hide text' : 'Show text'}</span></div>
      <div className={styles.control}><NeoButton type="button" variant="danger" className={`${styles.callButton} ${styles.end}`} onClick={onEnd} aria-label="End conversation"><CallIcon name="end" /></NeoButton><span>End session</span></div>
    </div>
    {voiceControl}
  </footer>;
}
