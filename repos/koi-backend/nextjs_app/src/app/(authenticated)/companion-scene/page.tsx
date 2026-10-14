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
  const [female, setFemale] = useState(false), [avatarEnabled, setAvatarEnabled] = useState(true);
  useEffect(() => {
    let cancelled = false;
    if (user) void db.users.where('uid').equals(user.uid).first().then((profile) => { if (!cancelled) setFemale(profile?.avatar === 'female_human'); }).catch(() => {});
    return () => { cancelled = true; };
  }, [user?.uid]);
  const leave = () => { chat.cancel(); router.push('/chat'); };
  return <CompanionScene companionName={female ? 'Aisha' : 'Raza'} modelUrl={`/models/koi-${female ? 'female' : 'male'}.vrm`}
    backLabel="Back to chat" avatarEnabled={avatarEnabled} onAvatarFailure={() => setAvatarEnabled(false)} viewportOffset={66}
    emotion={chat.currentEmotion} emotionIntensity={chat.currentIntensity} conversationState={chat.conversationState}
    messages={chat.messages.map((message) => ({ id: message.id, speaker: message.sender === 'user' ? 'user' : 'companion', text: message.content }))}
    subtitle={chat.subtitle || 'Start a text conversation with KOI.'} onBack={leave} onEnd={leave}
    notice={avatarEnabled ? 'Text conversation. Avatar speaking movements do not play audio.' : 'Text-only mode: the avatar is unavailable.'}
    composer={<ChatComposer onSend={chat.send} onCancel={chat.cancel} pending={chat.pending} error={chat.error} disabled={chat.blocked} onFocusChange={(focused) => chat.session.inputFocused(focused)} />} />;
}
