'use client';
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { useAuth } from '@/contexts/AuthContext';
import { useChat } from '@/hooks/useChat';
import { useAvatarPreference } from '@/hooks/useAvatarPreference';
import CompanionScene from '@/components/companion/CompanionScene';
import { companionHeaderTitle } from '@/components/companion/CompanionHeader';
import ChatComposer from '@/components/companion/ChatComposer';
import VoiceToggle from '@/components/companion/VoiceToggle';
import { hasVoice, speechBaseUrl, useVoiceEnabled, voiceCompanion } from '@/lib/speech/replyVoicePolicy';
import { useSpokenReplies } from '@/lib/speech/useSpokenReplies';
import { modeUsesCamera, modeUsesMic, useInputMode } from '@/contexts/InputModeContext';
import MicButton from '@/components/voice/MicButton';
import CameraPip from '@/components/camera/CameraPip';
import CallIcon from '@/components/companion/CallIcon';
import styles from '@/components/companion/CompanionScene.module.css';
import type { ChatServerEvent } from '@/lib/conversation/chatContract';
/** A crisis handoff or a high-risk result pauses the camera until the turn is resolved. */
const crisisActive = (events: ReadonlyArray<{ event: ChatServerEvent }>) => events.some(({ event }) => event.event === 'handoff'
  || (event.event === 'risk' && event.data.status === 'ok' && (event.data.risk_category === 'HIGH' || event.data.risk_category === 'CRITICAL')));
export default function AuthenticatedCompanionChat() {
  const { user, loading: authLoading } = useAuth(); const chat = useChat(); const router = useRouter();
  const avatarPreference = useAvatarPreference(user?.uid, authLoading);
  const [avatarEnabled, setAvatarEnabled] = useState(true);
  const preference = avatarPreference.status === 'ready' ? avatarPreference.preference : null;
  const selected = preference?.status === 'selected' ? preference : null;
  const legacyFox = selected?.avatar === 'fox';
  const avatarUnavailable = avatarPreference.status === 'error' || (avatarPreference.status === 'ready' && preference?.status === 'unselected');
  const avatarReady = avatarPreference.status === 'ready' && !!selected && !legacyFox;
  const companionName = companionHeaderTitle(selected);
  useEffect(() => { setAvatarEnabled(true); }, [user?.uid, selected?.modelUrl]);
  const speechBase = speechBaseUrl(); const speechCompanion = voiceCompanion(selected?.companion);
  const [voiceStored, setVoiceStored] = useVoiceEnabled(user?.uid);
  const voice = useSpokenReplies({ enabled: voiceStored, uid: user?.uid, companion: speechCompanion, messages: chat.messages, pending: chat.pending,
    serverEvents: chat.serverEvents, baseUrl: speechBase, getToken: () => user ? user.getIdToken() : Promise.reject(new Error('Signed out')) });
  const { mode } = useInputMode();
  const micOn = modeUsesMic(mode), cameraMode = modeUsesCamera(mode);
  // Choosing a video mode opens the camera; the control row (or the view itself) can turn it off again.
  const [cameraVisible, setCameraVisible] = useState(true);
  useEffect(() => { setCameraVisible(true); }, [mode]);
  const leave = () => router.push('/chat');
  const end = () => { voice.stop(); chat.cancel(); router.push('/chat'); };
  const noticeText = avatarPreference.status === 'loading'
    ? 'Loading your saved companion…'
    : avatarUnavailable
      ? 'Your saved companion could not be loaded. Text conversation remains available; review your selection in onboarding.'
      : legacyFox
        ? 'Your saved Koi fox choice is preserved. This viewer currently supports the male and female VRM models; text conversation remains available.'
        : !avatarEnabled ? 'Text-only mode: the avatar is unavailable.'
          : cameraMode ? 'Your camera view stays on this device: KOI does not record, send or analyse it.' : '';
  const inputHint = micOn ? 'Tap the mic to talk, or type. Your recording is sent to KOI for transcription and is not stored.' : 'Typing mode. Choose Audio in Mode to talk with your microphone.';
  return <CompanionScene companionName={companionName} modelUrl={avatarReady ? selected?.modelUrl ?? undefined : undefined}
    backLabel="Back to chat" avatarEnabled={avatarReady && avatarEnabled} onAvatarFailure={() => setAvatarEnabled(false)} viewportOffset={66}
    emotion={chat.currentEmotion} emotionIntensity={chat.currentIntensity} conversationState={chat.conversationState}
    consumeUiEvent={chat.session.consumeUiEvent} isHandoffResolved={chat.session.isHandoffResolved}
    serverEvents={chat.serverEvents} exerciseControlsDisabled={chat.pending || !!chat.clientEventPending}
    onExerciseRequest={(event) => { voice.stop(); void chat.session.sendClientEvent(event); }}
    onQueueClientEvent={(event) => chat.session.queueClientEvent(event)}
    onCrisisResolution={(path, handoff) => chat.session.queueCrisisPath(path, handoff)}
    messages={chat.messages.map((message) => ({ id: message.id, speaker: message.sender === 'user' ? 'user' : 'companion', text: message.content }))}
    speechSource={voice.speechSource}
    voiceControl={<VoiceToggle checked={voiceStored} onChange={setVoiceStored} configured={!!speechBase} companionHasVoice={hasVoice(speechCompanion)} signedIn={!!user} line={voice.line} />}
    subtitle={chat.subtitle || 'Start a text conversation with KOI.'} subtitleUpdating={chat.pending} onBack={leave} onEnd={end}
    notice={noticeText || (avatarReady && !avatarEnabled) || avatarUnavailable || legacyFox ? <>{noticeText}
      {avatarReady && !avatarEnabled && <> <button type="button" onClick={() => setAvatarEnabled(true)} style={{ minHeight: 44, padding: '8px 16px' }}>Retry avatar</button></>}
      {(avatarUnavailable || legacyFox) && <> <Link href="/onboarding">Review companion selection</Link></>}</> : undefined}
    micControl={micOn ? <MicButton key={user?.uid} className={styles.callButton} disabled={chat.pending || chat.blocked}
      onRecorded={(audio) => { voice.stop(); void chat.sendVoice(audio); }} /> : undefined}
    cameraControl={cameraMode ? <><button type="button" className={`${styles.callButton} ${cameraVisible ? styles.active : ''}`} aria-pressed={cameraVisible}
      aria-label={cameraVisible ? 'Turn camera off' : 'Turn camera on'} onClick={() => setCameraVisible((visible) => !visible)}><CallIcon name="camera" /></button>
      <span>{cameraVisible ? 'Camera on' : 'Camera off'}</span></> : undefined}
    cameraOverlay={cameraMode && cameraVisible ? <CameraPip enabled ownerUid={user?.uid ?? null} suspended={crisisActive(chat.serverEvents)} onClose={() => setCameraVisible(false)} /> : undefined}
    composer={<ChatComposer onSend={(text) => { voice.stop(); return chat.send(text); }} audioPlaying={voice.audioPlaying} onCancel={chat.cancel} pending={chat.pending} error={chat.error} disabled={chat.blocked} onFocusChange={(focused) => chat.session.inputFocused(focused)} idleHint={inputHint} />} />;
}
