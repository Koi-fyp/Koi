'use client';
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import CompanionScene from '@/components/companion/CompanionScene';
import ChatComposer from '@/components/companion/ChatComposer';
import { useConversationSession } from '@/hooks/useConversationSession';
import { createMockChatAdapter, MOCK_SAMPLES } from './mockChatAdapter';
export default function MockChatSession() {
  const [adapter] = useState(createMockChatAdapter);
  const chat = useConversationSession(adapter);
  const [avatarEnabled, setAvatarEnabled] = useState(true);
  const [model, setModel] = useState<'male' | 'female'>('male'); const router = useRouter();
  const leave = () => { chat.cancel(); router.push('/'); };
  return <CompanionScene companionName={model === 'male' ? 'Raza' : 'Aisha'} modelUrl={`/models/koi-${model}.vrm`} exposeController
    avatarEnabled={avatarEnabled} onAvatarFailure={() => setAvatarEnabled(false)}
    emotion={chat.companion.emotion} emotionIntensity={chat.companion.intensity} conversationState={chat.conversationState}
    messages={chat.messages.map((message) => ({ id: message.id, speaker: message.sender === 'user' ? 'user' : 'companion', text: message.content + (message.status === 'failed' || message.status === 'cancelled' ? ` (${message.status})` : '') }))}
    subtitle={chat.subtitle || 'Development-only JSON chat simulation. Choose a scripted sample.'} onBack={leave} onEnd={leave}
    notice="Development-only mock chat. Scripted samples only; nothing is transmitted or saved."
    transcriptNotice="Mock adapter uses the real JSON schema. No Firebase, tokens or AI inference."
    composer={<><div style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'center', gap: 5, marginBottom: 8 }}>
      {MOCK_SAMPLES.map((sample) => <button key={sample} type="button" onClick={() => void chat.send(sample)} style={{ fontSize: 10, padding: '6px 8px', border: '1px solid #c9b6a5', borderRadius: 8, background: '#fffaf6' }}>{sample}</button>)}</div>
      <ChatComposer onSend={chat.send} onCancel={chat.cancel} pending={chat.pending} error={chat.error} onFocusChange={(focused) => chat.session.inputFocused(focused)} development /></>}
    settings={<>{!avatarEnabled && <button type="button" onClick={() => setAvatarEnabled(true)}>Show avatar</button>}<label>Preview model<select aria-label="Preview model" value={model} onChange={(event) => setModel(event.target.value as 'male' | 'female')}><option value="male">Male</option><option value="female">Female</option></select></label></>} />;
}
