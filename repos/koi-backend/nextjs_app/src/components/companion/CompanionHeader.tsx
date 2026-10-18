import CallIcon from './CallIcon';
import styles from './CompanionScene.module.css';
import type { ResolvedAvatarPreference } from '@/lib/avatar/avatarPreference';
/** Header title: the human companion's name; the fox and an unselected/unloaded preference are "KOI". */
export function companionHeaderTitle(preference: ResolvedAvatarPreference | null | undefined): string {
  if (preference?.status !== 'selected' || preference.companion === 'koi') return 'KOI';
  return preference.displayName || preference.name;
}
export default function CompanionHeader({ name, onBack, onSettings, settingsOpen, backLabel = 'Back to chat' }: {
  name: string; onBack: () => void; onSettings?: () => void; settingsOpen: boolean; backLabel?: string;
}) {
  return <header className={styles.header}>
    <button type="button" className={styles.iconButton} onClick={onBack} aria-label={backLabel}><CallIcon name="back" /></button>
    <div className={styles.identity}><div><h1>{name}</h1><p>Avatar conversation</p></div></div>
    {onSettings && <button type="button" className={styles.iconButton} onClick={onSettings} aria-label="Preview settings" aria-expanded={settingsOpen} aria-controls="companion-settings"><CallIcon name="settings" /></button>}
  </header>;
}
