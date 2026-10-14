import styles from './CompanionScene.module.css';
export default function ConversationSubtitles({ text, language, updating = false }: {
  text: string; language?: 'en' | 'ur'; updating?: boolean;
}) {
  return <section className={styles.subtitles} aria-label="Companion subtitles" aria-live="polite" aria-atomic="true" aria-busy={updating}>
    <span className={styles.subtitleLabel}>KOI</span>
    <p dir="auto" lang={language}>{text}</p>
  </section>;
}
