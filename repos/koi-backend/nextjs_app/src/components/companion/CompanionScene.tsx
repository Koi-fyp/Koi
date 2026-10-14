'use client';
import type { SpeechTimeline } from '@/lib/speech/mouthCues';
import { useRef, useState, type ReactNode } from 'react';
import type { KoiEmotion, ConversationState } from '@/components/avatar/VRMAvatarController';
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
  emotion?: KoiEmotion;
  emotionIntensity?: number;
  conversationState?: ConversationState;
  exposeController?: boolean;
  messages: ConversationMessage[];
  subtitle: string;
  subtitleLanguage?: 'en' | 'ur';
  subtitleUpdating?: boolean;
  onBack: () => void;
  onEnd: () => void;
  notice?: string;
  transcriptNotice?: string;
  settings?: ReactNode;
  composer?: ReactNode;
  avatarEnabled?: boolean;
  onAvatarFailure?: () => void;
  viewportOffset?: number;
  backLabel?: string;
  speechSource?: SpeechTimeline;
  onAvatarReady?: () => void;
}
export default function CompanionScene({ companionName, modelUrl, messages, subtitle, subtitleLanguage,
  subtitleUpdating, onBack, onEnd, notice, transcriptNotice, settings, emotion, emotionIntensity, conversationState, exposeController, composer, avatarEnabled = true, onAvatarFailure, viewportOffset = 0, backLabel, speechSource, onAvatarReady }: CompanionSceneProps) {
  const [textOpen, setTextOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const toggleRef = useRef<HTMLButtonElement>(null);
  const closeText = () => { setTextOpen(false); toggleRef.current?.focus(); };
  return <main className={styles.scene} style={viewportOffset ? { height: `calc(100dvh - ${viewportOffset}px)` } : undefined} onKeyDown={(event) => {
    if (event.key === 'Escape') { if (textOpen) closeText(); setSettingsOpen(false); }
  }}>
    <CompanionHeader backLabel={backLabel} name={companionName} onBack={onBack} onSettings={settings ? () => setSettingsOpen((open) => !open) : undefined} settingsOpen={settingsOpen} />
    {notice && <p className={styles.notice}>{notice}</p>}
    {settingsOpen && <section id="companion-settings" className={styles.settings} aria-label="Development preview settings">{settings}</section>}
    <div className={`${styles.workspace} ${textOpen && avatarEnabled ? styles.withText : ''}`}>
      {avatarEnabled && <section className={styles.stage} aria-label="Companion avatar">
        <div className={styles.renderer}><VRMAvatarRenderer modelUrl={modelUrl} emotion={emotion} emotionIntensity={emotionIntensity} conversationState={conversationState} exposeController={exposeController} speechSource={speechSource} onReady={onAvatarReady} onLoadError={onAvatarFailure} minHeight={0} maxPixelRatio={1.5} /></div>
        <ConversationSubtitles text={subtitle} language={subtitleLanguage} updating={subtitleUpdating} />
      </section>}
      {(textOpen || !avatarEnabled) && <ConversationTextPanel messages={messages} companionName={companionName} notice={transcriptNotice} allowClose={avatarEnabled} onClose={closeText} />}
    </div>
    {composer && <div style={{ flexShrink: 0, paddingTop: 10 }}>{composer}</div>}
    <ConversationControls textOpen={textOpen || !avatarEnabled} textLocked={!avatarEnabled} toggleRef={toggleRef} onToggleText={() => setTextOpen((open) => !open)} onEnd={onEnd} />
  </main>;
}
