import CallIcon from './CallIcon';
import styles from './CompanionScene.module.css';
export default function CompanionHeader({ name, onBack, onSettings, settingsOpen }: {
  name: string; onBack: () => void; onSettings?: () => void; settingsOpen: boolean;
}) {
  return <header className={styles.header}>
    <button type="button" className={styles.iconButton} onClick={onBack} aria-label="Back to sandbox"><CallIcon name="back" /></button>
    <div className={styles.identity}><span className={styles.wordmark}>KOI</span><div><h1>{name}</h1><p>Avatar conversation</p></div></div>
    {onSettings && <button type="button" className={styles.iconButton} onClick={onSettings} aria-label="Preview settings" aria-expanded={settingsOpen} aria-controls="companion-settings"><CallIcon name="settings" /></button>}
  </header>;
}
