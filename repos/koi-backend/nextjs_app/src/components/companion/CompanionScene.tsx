'use client';
import { useRef, useState, type ReactNode } from 'react';
import VRMAvatarRenderer from '@/components/avatar/VRMAvatarRenderer';
import CompanionHeader from './CompanionHeader';
import ConversationControls from './ConversationControls';
import ConversationSubtitles from './ConversationSubtitles';
import ConversationTextPanel from './ConversationTextPanel';
import type { ConversationMessage } from './types';
import styles from './CompanionScene.module.css';

export interface CompanionSceneProps {
  companionName: string;
  modelUrl?: string;
  messages: ConversationMessage[];
  subtitle: string;
  subtitleLanguage?: 'en' | 'ur';
  subtitleUpdating?: boolean;
  onBack: () => void;
  onEnd: () => void;
  notice?: string;
  transcriptNotice?: string;
  settings?: ReactNode;
}
export default function CompanionScene({ companionName, modelUrl, messages, subtitle, subtitleLanguage,
  subtitleUpdating, onBack, onEnd, notice, transcriptNotice, settings }: CompanionSceneProps) {
  const [textOpen, setTextOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const toggleRef = useRef<HTMLButtonElement>(null);
  const closeText = () => { setTextOpen(false); toggleRef.current?.focus(); };
  return <main className={styles.scene} onKeyDown={(event) => {
    if (event.key === 'Escape') { if (textOpen) closeText(); setSettingsOpen(false); }
  }}>
    <CompanionHeader name={companionName} onBack={onBack} onSettings={settings ? () => setSettingsOpen((open) => !open) : undefined} settingsOpen={settingsOpen} />
    {notice && <p className={styles.notice}>{notice}</p>}
    {settingsOpen && <section id="companion-settings" className={styles.settings} aria-label="Development preview settings">{settings}</section>}
    <div className={`${styles.workspace} ${textOpen ? styles.withText : ''}`}>
      <section className={styles.stage} aria-label="Companion avatar">
        <div className={styles.renderer}><VRMAvatarRenderer modelUrl={modelUrl} minHeight={0} maxPixelRatio={1.5} /></div>
        <ConversationSubtitles text={subtitle} language={subtitleLanguage} updating={subtitleUpdating} />
      </section>
      {textOpen && <ConversationTextPanel messages={messages} companionName={companionName} notice={transcriptNotice} onClose={closeText} />}
    </div>
    <ConversationControls textOpen={textOpen} toggleRef={toggleRef} onToggleText={() => setTextOpen((open) => !open)} onEnd={onEnd} />
  </main>;
}
