import { useEffect, useRef } from 'react';
import type { ConversationMessage } from './types';
import CallIcon from './CallIcon';
import styles from './CompanionScene.module.css';
export default function ConversationTextPanel({ messages, companionName, onClose, notice }: {
  messages: ConversationMessage[]; companionName: string; onClose: () => void; notice?: string;
}) {
  const closeRef = useRef<HTMLButtonElement>(null);
  const logRef = useRef<HTMLDivElement>(null);
  useEffect(() => { closeRef.current?.focus(); }, []);
  useEffect(() => { if (logRef.current) logRef.current.scrollTop = logRef.current.scrollHeight; }, [messages]);
  return <aside id="conversation-text" className={styles.textPanel} aria-label="Text conversation panel">
    <div className={styles.panelHeader}><h2>Conversation</h2><button ref={closeRef} type="button" className={styles.iconButton} onClick={onClose} aria-label="Close text conversation"><CallIcon name="close" /></button></div>
    <div ref={logRef} className={styles.messages} role="log" aria-live="polite" aria-label="Conversation transcript">
      {messages.map((message) => <div key={message.id} className={`${styles.message} ${message.speaker === 'user' ? styles.userMessage : ''}`}>
        <span>{message.speaker === 'user' ? 'You' : companionName}</span>
        <p lang={message.language} dir="auto">{message.text}</p>
      </div>)}
    </div>
    {notice && <p className={styles.panelNotice}>{notice}</p>}
  </aside>;
}
