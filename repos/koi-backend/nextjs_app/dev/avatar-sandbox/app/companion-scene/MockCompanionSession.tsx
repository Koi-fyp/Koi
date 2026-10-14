'use client';
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import CompanionScene from '@/components/companion/CompanionScene';
import type { ConversationMessage } from '@/components/companion/types';

const english = "You don't have to figure everything out today.\nWe can take this one small step at a time.";
const urdu = "\u0622\u062c \u0633\u0628 \u06a9\u0686\u06be \u0633\u0644\u062c\u06be\u0627\u0646\u0627 \u0636\u0631\u0648\u0631\u06cc \u0646\u06c1\u06cc\u06ba\u06d4\n\u06c1\u0645 \u0622\u06c1\u0633\u062a\u06c1 \u0622\u06c1\u0633\u062a\u06c1\u060c \u0627\u06cc\u06a9 \u0642\u062f\u0645 \u0627\u06cc\u06a9 \u0648\u0642\u062a \u0645\u06cc\u06ba \u0622\u06af\u06d2 \u0628\u0691\u06be \u0633\u06a9\u062a\u06d2 \u06c1\u06cc\u06ba\u06d4";
const messages: ConversationMessage[] = [
  { id: '1', speaker: 'companion', text: "It's good to see you. How has your day been?", language: 'en' },
  { id: '2', speaker: 'user', text: "A little overwhelming. I could use a quiet moment.", language: 'en' },
  { id: '3', speaker: 'companion', text: english, language: 'en' },
  { id: '4', speaker: 'companion', text: urdu, language: 'ur' },
];
export default function MockCompanionSession() {
  const [model, setModel] = useState<'male' | 'female'>('male');
  const [language, setLanguage] = useState<'en' | 'ur'>('en');
  const router = useRouter();
  return <CompanionScene companionName={model === 'male' ? 'Raza' : 'Aisha'} modelUrl={`/models/koi-${model}.vrm`}
    messages={messages} subtitle={language === 'en' ? english : urdu} subtitleLanguage={language}
    onBack={() => router.push('/')} onEnd={() => router.push('/')}
    notice="Development-only mock session &#183; Scripted content, not AI-generated"
    transcriptNotice="Development mock transcript &#183; No messages are sent or saved"
    settings={<><label>Preview model<select aria-label="Preview model" value={model} onChange={(event) => setModel(event.target.value as 'male' | 'female')}><option value="male">Raza &middot; Male (default)</option><option value="female">Aisha &middot; Female (preview)</option></select></label>
      <label>Subtitle language<select aria-label="Subtitle language" value={language} onChange={(event) => setLanguage(event.target.value as 'en' | 'ur')}><option value="en">English</option><option value="ur">Urdu</option></select></label>
      <p>Local development previews only. Microphone and camera are unavailable.</p></>} />;
}
