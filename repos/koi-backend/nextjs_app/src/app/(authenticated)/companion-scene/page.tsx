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
  const leave = () => router.push('/chat');
  const end = () => { voice.stop(); chat.cancel(); router.push('/chat'); };
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
    notice={<>{avatarPreference.status === 'loading'
      ? 'Loading your saved companion…'
      : avatarUnavailable
        ? 'Your saved companion could not be loaded. Text conversation remains available; review your selection in onboarding.'
        : legacyFox
          ? 'Your saved Koi fox choice is preserved. This viewer currently supports the male and female VRM models; text conversation remains available.'
          : avatarEnabled ? voice.audioPlaying ? 'Text is the only available input mode. A spoken reply is playing; the text is unchanged.' : 'Text is the only available input mode. Audio and video modes are not enabled yet; avatar speaking movements do not play audio.' : 'Text-only mode: the avatar is unavailable.'}
      {avatarReady && !avatarEnabled && <> <button type="button" onClick={() => setAvatarEnabled(true)} style={{ minHeight: 44, padding: '8px 16px' }}>Retry avatar</button></>}
      {(avatarUnavailable || legacyFox) && <> <Link href="/onboarding">Review companion selection</Link></>}</>}
    composer={<ChatComposer onSend={(text) => { voice.stop(); return chat.send(text); }} audioPlaying={voice.audioPlaying} onCancel={chat.cancel} pending={chat.pending} error={chat.error} disabled={chat.blocked} onFocusChange={(focused) => chat.session.inputFocused(focused)} />} />;
}
