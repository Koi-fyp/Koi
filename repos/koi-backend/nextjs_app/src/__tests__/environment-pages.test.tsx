import React from 'react';
import { act, render } from '@testing-library/react';
import type { ChatServerEvent } from '@/lib/conversation/chatContract';
import { ConversationSession } from '@/lib/conversation/ConversationSession';
import { EnvironmentProvider, EnvironmentSession } from '@/contexts/EnvironmentContext';
import ChatPage from '@/app/(authenticated)/chat/page';
import BottomNav from '@/components/layout/BottomNav';
import CompanionScene from '@/components/companion/CompanionScene';

let mockPath = '/chat';
jest.mock('next/navigation', () => ({ usePathname: () => mockPath }));
jest.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: { uid: 'fixture' }, loading: false }) }));
jest.mock('@/hooks/useChat', () => ({ useChat: () => ({ messages: [], isTyping: false, serverEvents: [], send: jest.fn() }) }));
jest.mock('@/hooks/useAvatarPreference', () => ({ useAvatarPreference: () => ({ status: 'ready', preference: { status: 'selected', avatar: 'fox' } }) }));
jest.mock('@/components/chat/ConversationProductControls', () => ({ __esModule: true, default: () => null }));
jest.mock('@/components/chat/MessageList', () => ({ __esModule: true, default: () => null }));
jest.mock('@/components/companion/CompanionScene.module.css', () => ({}));
jest.mock('@/components/avatar/VRMAvatarRenderer', () => ({ __esModule: true, default: () => null }));

it('applies each palette to actual pages, shares Chat nav tint, and leaves nav mounted on route/session changes', () => {
  let emit!: (event: ChatServerEvent) => void;
  const session = new ConversationSession({ send: (_request, options) => new Promise(() => { emit = event => options?.onEvent?.(event); }) });
  const wrap = (route: 'chat' | 'call', selectedSession = session) => <EnvironmentProvider><BottomNav />
    <EnvironmentSession key={selectedSession.conversationId} session={selectedSession}>
      {route === 'chat' ? <ChatPage /> : <CompanionScene companionName="Fixture" messages={[]} subtitle="" onBack={() => {}} onEnd={() => {}} />}
    </EnvironmentSession>
  </EnvironmentProvider>;
  const view = render(wrap('chat'));
  const navigation = view.getByRole('navigation');
  act(() => { void session.send('Hello'); emit({ event: 'companion_state', data: { emotion: 'joy', intensity: 1 } }); });
  expect(view.container.querySelector('[data-environment]')).toHaveStyle({ backgroundColor: '#FFE2B8' });
  expect(navigation).toHaveStyle({ backgroundColor: '#FFE2B8' });
  mockPath = '/companion-scene'; view.rerender(wrap('call'));
  expect(view.container.querySelector('[data-environment]')).toHaveStyle({ backgroundColor: '#FFE0A3' });
  expect(view.getByRole('navigation')).toBe(navigation);
  expect(navigation).toHaveStyle({ backgroundColor: '#FFE5D9' });
  act(() => emit({ event: 'risk', data: { status: 'ok', risk_category: 'CRITICAL' } } as ChatServerEvent));
  expect(view.container.querySelector('[data-environment]')).toHaveStyle({ backgroundColor: '#C1D9D8' });
  mockPath = '/chat'; view.rerender(wrap('chat'));
  expect(view.container.querySelector('[data-environment]')).toHaveStyle({ backgroundColor: '#DADED8' });
  expect(navigation).toHaveStyle({ backgroundColor: '#DADED8' });
  view.rerender(wrap('chat', new ConversationSession({ send: jest.fn() })));
  expect(view.container.querySelector('[data-environment]')).toHaveStyle({ backgroundColor: '#FFE5D9' });
  expect(view.getByRole('navigation')).toBe(navigation);
});
