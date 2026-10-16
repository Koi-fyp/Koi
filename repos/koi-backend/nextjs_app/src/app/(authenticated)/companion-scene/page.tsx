'use client';
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/contexts/AuthContext';
import { useChat } from '@/hooks/useChat';
import { db } from '@/lib/db';
import CompanionScene from '@/components/companion/CompanionScene';
import ChatComposer from '@/components/companion/ChatComposer';
export default function AuthenticatedCompanionChat() {
  const { user } = useAuth(); const chat = useChat(); const router = useRouter();
  const [female, setFemale] = useState(false), [legacyFox, setLegacyFox] = useState(false), [avatarEnabled, setAvatarEnabled] = useState(true);
  useEffect(() => {
    let cancelled = false;
    if (user) void db.users.where('uid').equals(user.uid).first().then((profile) => {
      if (!cancelled) { setFemale(profile?.avatar === 'female_human'); setLegacyFox(profile?.avatar === 'fox'); }
    }).catch(() => {});
    return () => { cancelled = true; };
  }, [user?.uid]);
  const leave = () => { chat.cancel(); router.push('/chat'); };
  return <CompanionScene companionName={female ? 'Aisha' : 'Raza'} modelUrl={`/models/koi-${female ? 'female' : 'male'}.vrm`}
    backLabel="Back to chat" avatarEnabled={avatarEnabled && !legacyFox} onAvatarFailure={() => setAvatarEnabled(false)} viewportOffset={66}
    emotion={chat.currentEmotion} emotionIntensity={chat.currentIntensity} conversationState={chat.conversationState}
    serverEvents={chat.serverEvents} exerciseControlsDisabled={chat.pending || !!chat.clientEventPending}
    onExerciseRequest={(event) => { void chat.session.sendClientEvent(event); }}
    onQueueClientEvent={(event) => chat.session.queueClientEvent(event)}
    onCrisisResolution={(path, handoff) => chat.session.queueCrisisPath(path, handoff)}
    messages={chat.messages.map((message) => ({ id: message.id, speaker: message.sender === 'user' ? 'user' : 'companion', text: message.content }))}
    subtitle={chat.subtitle || 'Start a text conversation with KOI.'} subtitleUpdating={chat.pending} onBack={leave} onEnd={leave}
    notice={legacyFox
      ? 'Your saved KOI fox avatar choice is preserved. This viewer currently supports the male and female VRM models; text conversation remains available.'
      : avatarEnabled ? 'Text is the only available input mode. Audio and video modes are not enabled yet; avatar speaking movements do not play audio.' : 'Text-only mode: the avatar is unavailable.'}
    composer={<ChatComposer onSend={chat.send} onCancel={chat.cancel} pending={chat.pending} error={chat.error} disabled={chat.blocked} onFocusChange={(focused) => chat.session.inputFocused(focused)} />} />;
}
