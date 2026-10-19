'use client';
// Browser verification fixture in the separate development app; no production route.
import { useRef, useState } from 'react';
import { EnvironmentProvider, EnvironmentSession, useEnvironment } from '@/contexts/EnvironmentContext';
import { ConversationSession } from '@/lib/conversation/ConversationSession';
import { useConversationSession } from '@/hooks/useConversationSession';
import type { ChatServerEvent } from '@/lib/conversation/chatContract';
import CompanionScene from '@/components/companion/CompanionScene';
import ChatComposer from '@/components/companion/ChatComposer';
import MessageBubble from '@/components/chat/MessageBubble';
import InputBar from '@/components/chat/InputBar';

const unusedAdapter = { send: async () => { throw new Error('Fixture uses its shared session'); } };
export default function EnvironmentCheck() {
  return <EnvironmentProvider><Fixture /></EnvironmentProvider>;
}
function Fixture() {
  const emit = useRef<(event: ChatServerEvent) => void>(() => {});
  const [session] = useState(() => new ConversationSession({ send: (_request, options) => new Promise(() => {
    emit.current = event => options?.onEvent?.(event);
  }) }));
  return <EnvironmentSession session={session}><Surfaces session={session} emit={event => emit.current(event)} /></EnvironmentSession>;
}
function Surfaces({ session, emit }: { session: ConversationSession; emit: (event: ChatServerEvent) => void }) {
  const chat = useConversationSession(unusedAdapter, [], session);
  const environment = useEnvironment('chat');
  return <>
    <div aria-label="Fixture controls">
      <button onClick={() => { void session.send('Fixture turn'); }}>New turn</button>
      {['neutral', 'joy', 'angry', 'sorrow', 'fun'].map(emotion => <button key={emotion} onClick={() => emit({ event: 'companion_state', data: { emotion: emotion as 'joy', intensity: 0.7 } })}>{emotion}</button>)}
      <button onClick={() => emit({ event: 'ui_action', data: { name: 'start_breathing', args: { inhale_s: 1, exhale_s: 1, cycles: 1, cue_audio: ['In', 'Out'] } } })}>Start fixture breathing</button>
      <button onClick={() => emit({ event: 'risk', data: { status: 'ok', risk_category: 'HIGH' } } as ChatServerEvent)}>HIGH fixture</button>
    </div>
    <div data-testid="chat-surface" className="environment-background" style={{ backgroundColor: environment.backgroundColor }}>
      <MessageBubble message={{ id: 'fixture', conversationId: session.conversationId, sender: 'user', content: 'User body contrast fixture', timestamp: new Date(), status: 'completed', emotion: 'neutral' }} />
      <InputBar onSend={() => {}} />
    </div>
    <CompanionScene companionName="Fixture" avatarEnabled={false} messages={[
      { id: 'user', speaker: 'user', text: 'Call user body fixture' },
      { id: 'ai', speaker: 'companion', text: 'Call companion body fixture' },
    ]} subtitle="" notice="Call status fixture" transcriptNotice="Call transcript notice fixture" onBack={() => {}} onEnd={() => {}}
      serverEvents={chat.serverEvents} consumeUiEvent={session.consumeUiEvent} isHandoffResolved={session.isHandoffResolved}
      onExerciseRequest={() => {}} onQueueClientEvent={event => session.queueClientEvent(event)}
      onCrisisResolution={(path, handoff) => session.queueCrisisPath(path, handoff)}
      composer={<ChatComposer onSend={async () => {}} pending={false} error={null} onCancel={() => {}} onFocusChange={() => {}} />} />
  </>;
}
