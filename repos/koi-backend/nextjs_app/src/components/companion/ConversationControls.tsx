import type { RefObject } from 'react';
import NeoButton from '@/components/ui/NeoButton';
import CallIcon from './CallIcon';
import styles from './CompanionScene.module.css';
export default function ConversationControls({ textOpen, onToggleText, onEnd, toggleRef }: {
  textOpen: boolean; onToggleText: () => void; onEnd: () => void; toggleRef: RefObject<HTMLButtonElement>;
}) {
  return <footer className={styles.footer}>
    <div className={styles.controls} aria-label="Conversation controls">
      <div className={styles.control}><NeoButton type="button" className={styles.callButton} disabled aria-label="Microphone unavailable" title="Microphone is unavailable in this preview"><CallIcon name="microphone" /></NeoButton><span>Mic unavailable</span></div>
      <div className={styles.control}><NeoButton type="button" className={styles.callButton} disabled aria-label="Camera unavailable" title="Camera is unavailable in this preview"><CallIcon name="camera" /></NeoButton><span>Camera unavailable</span></div>
      <div className={styles.control}><button ref={toggleRef} type="button" className={`${styles.callButton} ${textOpen ? styles.active : ''}`} onClick={onToggleText} aria-label="Text conversation" aria-expanded={textOpen} aria-controls="conversation-text"><CallIcon name="text" /></button><span>{textOpen ? 'Hide text' : 'Show text'}</span></div>
      <div className={styles.control}><NeoButton type="button" variant="danger" className={`${styles.callButton} ${styles.end}`} onClick={onEnd} aria-label="End conversation"><CallIcon name="end" /></NeoButton><span>End session</span></div>
    </div>
  </footer>;
}
