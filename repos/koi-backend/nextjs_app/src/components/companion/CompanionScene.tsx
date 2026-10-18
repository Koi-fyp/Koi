'use client';
import type { SpeechTimeline } from '@/lib/speech/mouthCues';
import { useEffect, useRef, useState, type ReactNode } from 'react';
import type { KoiEmotion, ConversationState } from '@/components/avatar/VRMAvatarController';
import VRMAvatarRenderer from '@/components/avatar/VRMAvatarRenderer';
import CompanionHeader from './CompanionHeader';
import ConversationControls from './ConversationControls';
import ConversationSubtitles from './ConversationSubtitles';
import ConversationTextPanel from './ConversationTextPanel';
import type { ConversationMessage } from './types';
import type { ChatServerEvent, ExerciseClientEvent } from '@/lib/conversation/chatContract';
import styles from './CompanionScene.module.css';
import ExerciseDirector from './ExerciseDirector';
import CrisisHandoffDialog from './CrisisHandoffDialog';
import { riskInterventionForDisplay, type CrisisInterventionDisplay } from '@/lib/conversation/crisisContract';

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
  notice?: ReactNode;
  /** Page actions shown as a row under the header, always in view (not inside the scrolling tools panel). */
  actions?: ReactNode;
  transcriptNotice?: string;
  settings?: ReactNode;
  composer?: ReactNode;
  avatarEnabled?: boolean;
  onAvatarFailure?: () => void;
  viewportOffset?: number;
  backLabel?: string;
  speechSource?: SpeechTimeline;
  onAvatarReady?: () => void;
  consumeUiEvent?: (id: number) => boolean;
  isHandoffResolved?: (handoff: { to: 'crisis'; reason: string }) => boolean;
  serverEvents?: Array<{ id: number; event: ChatServerEvent }>;
  onExerciseRequest?: (event: ExerciseClientEvent) => void;
  onQueueClientEvent?: (event: ExerciseClientEvent) => void;
  exerciseControlsDisabled?: boolean;
  onCrisisResolution?: (path: import('@/lib/conversation/chatContract').CrisisPath, handoff: { to: 'crisis'; reason: string }) => void;
  crisisIntervention?: CrisisInterventionDisplay;
  voiceControl?: ReactNode;
  /** Working mic / camera controls for the control row; omitted ones show as off for the current mode. */
  micControl?: ReactNode;
  cameraControl?: ReactNode;
  /** Local camera self-view, shown over a corner of the avatar stage. */
  cameraOverlay?: ReactNode;
}
export default function CompanionScene({ companionName, modelUrl, messages, subtitle, subtitleLanguage,
  subtitleUpdating, onBack, onEnd, notice, actions, transcriptNotice, settings, emotion, emotionIntensity, conversationState, exposeController, composer, avatarEnabled = true, onAvatarFailure, viewportOffset = 0, backLabel, speechSource, onAvatarReady, serverEvents, onExerciseRequest, onQueueClientEvent, exerciseControlsDisabled, onCrisisResolution, crisisIntervention, consumeUiEvent, isHandoffResolved, voiceControl, micControl, cameraControl, cameraOverlay }: CompanionSceneProps) {
  const [textOpen, setTextOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [dismissedHandoffId, setDismissedHandoffId] = useState<number | null>(null);
  const [crisisSelectionQueued, setCrisisSelectionQueued] = useState(false);
  const toggleRef = useRef<HTMLButtonElement>(null);
  const activeCrisisRef = useRef<{ id: number; handoff: { to: 'crisis'; reason: string } } | null>(null);
  const closeText = () => { setTextOpen(false); toggleRef.current?.focus(); };
  const candidateHandoff = serverEvents?.find((item) => item.event.event === 'handoff');
  const highRiskEvent = serverEvents?.find((item) => item.event.event === 'risk'
    && item.event.data.status === 'ok' && (item.event.data.risk_category === 'HIGH' || item.event.data.risk_category === 'CRITICAL'));
  if (!serverEvents?.length) activeCrisisRef.current = null;
  if (!activeCrisisRef.current && (candidateHandoff || highRiskEvent)) {
    activeCrisisRef.current = candidateHandoff
      ? { id: candidateHandoff.id, handoff: candidateHandoff.event.event === 'handoff' ? candidateHandoff.event.data : { to: 'crisis', reason: '' } }
      : { id: highRiskEvent!.id, handoff: { to: 'crisis', reason: `server-risk-event-${highRiskEvent!.id}` } };
  }
  const activeCrisis = activeCrisisRef.current;
  const handoff = activeCrisis?.handoff;
  const handoffEventId = activeCrisis?.id ?? null;
  const riskForContent = highRiskEvent?.event.event === 'risk' ? riskInterventionForDisplay(highRiskEvent.event.data) : undefined;
  useEffect(() => { if (serverEvents?.length === 0) setCrisisSelectionQueued(false); }, [serverEvents]);
  return <main className={styles.scene} style={viewportOffset ? { height: `calc(100dvh - ${viewportOffset}px)` } : undefined} onKeyDown={(event) => {
    if (event.key === 'Escape') { if (textOpen) closeText(); setSettingsOpen(false); }
  }}>
    {/* The avatar owns ~70% of the height; every other control lives in the scrollable panel below. */}
    <div className={styles.stageArea}>
      <CompanionHeader backLabel={backLabel} name={companionName} onBack={onBack} onSettings={settings ? () => setSettingsOpen((open) => !open) : undefined} settingsOpen={settingsOpen} />
      {actions && <div className={styles.actions}>{actions}</div>}
      {settingsOpen && <section id="companion-settings" className={styles.settings} aria-label="Development preview settings">{settings}</section>}
      <div className={`${styles.workspace} ${textOpen && avatarEnabled ? styles.withText : ''}`}>
        {avatarEnabled && <section className={styles.stage} aria-label="Companion avatar">
          <div className={styles.renderer}><VRMAvatarRenderer modelUrl={modelUrl} emotion={emotion} emotionIntensity={emotionIntensity} conversationState={conversationState} exposeController={exposeController} speechSource={speechSource} onReady={onAvatarReady} onLoadError={onAvatarFailure} minHeight={0} maxPixelRatio={1.5} /></div>
          <ConversationSubtitles text={subtitle} language={subtitleLanguage} updating={subtitleUpdating} />
        </section>}
        {(textOpen || !avatarEnabled) && <ConversationTextPanel messages={messages} companionName={companionName} notice={transcriptNotice} allowClose={avatarEnabled} onClose={closeText} />}
        {cameraOverlay && <div className={styles.cameraOverlay}>{cameraOverlay}</div>}
      </div>
    </div>
    <section className={styles.panel} aria-label="Conversation tools">
      {crisisSelectionQueued && <p className={styles.notice} role="status">Your selection is saved for your next message.</p>}
      {composer}
      <ConversationControls textOpen={textOpen || !avatarEnabled} textLocked={!avatarEnabled} toggleRef={toggleRef} onToggleText={() => setTextOpen((open) => !open)} onEnd={onEnd} voiceControl={voiceControl}
        micControl={micControl} cameraControl={cameraControl} />
      {serverEvents && onExerciseRequest && onQueueClientEvent && <ExerciseDirector consumeEvent={consumeUiEvent} events={serverEvents} disabled={exerciseControlsDisabled} interruptKey={handoffEventId ?? 0}
        onRequest={onExerciseRequest} onQueueClientEvent={onQueueClientEvent} />}
      {notice && <div className={styles.notice}>{notice}</div>}
    </section>
    <CrisisHandoffDialog open={!!handoff && !isHandoffResolved?.(handoff) && handoffEventId !== dismissedHandoffId && !!onCrisisResolution} content={crisisIntervention ?? riskForContent}
      onChoose={(path) => { if (handoff && handoffEventId !== null && onCrisisResolution) { onCrisisResolution(path, handoff); setDismissedHandoffId(handoffEventId); setCrisisSelectionQueued(true); } }} />
  </main>;
}
