/** @jest-environment jsdom */
import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';

const mockUseAuth = jest.fn();
const mockUseChat = jest.fn();
jest.mock('@/contexts/AuthContext', () => ({ useAuth: () => mockUseAuth() }));
jest.mock('@/hooks/useChat', () => ({ useChat: () => mockUseChat() }));
jest.mock('@/contexts/ConversationContext', () => { const snapshot = { loading: false, error: null, completing: false, switching: false, hasQualifyingPair: false, hasUnresolvedHandoff: false }; const manager = { uid: 'fixture', session: null, subscribe: () => () => {}, getSnapshot: () => snapshot }; return { useSharedConversation: () => manager, useOwnedConversationActions: () => ({ createOwned: async () => ({}), openOwned: async () => ({}) }) }; });
jest.mock('@/components/companion/CompanionScene.module.css', () => ({}));
jest.mock('@/components/companion/CompanionScene', () => ({
  __esModule: true,
  default: (props: { companionName: string; modelUrl?: string; avatarEnabled?: boolean; notice?: React.ReactNode; onAvatarFailure?: () => void; emotion?: string; emotionIntensity?: number }) => (
    <div data-testid="scene" data-name={props.companionName} data-model={props.modelUrl ?? ''} data-avatar-enabled={String(props.avatarEnabled)} data-emotion={props.emotion} data-intensity={props.emotionIntensity}>
      <button onClick={props.onAvatarFailure}>Simulate model failure</button>
      {props.notice}
    </div>
  ),
}));

import CompanionPage from '@/app/(authenticated)/companion-scene/page';
import { db } from '@/lib/db';

describe('authenticated companion avatar selection path', () => {
  beforeEach(async () => {
    mockUseAuth.mockReturnValue({ user: { uid: 'uid-a' }, loading: false });
    mockUseChat.mockReturnValue({
      currentEmotion: 'neutral', currentIntensity: 0, conversationState: 'idle', serverEvents: [],
      pending: false, clientEventPending: false, messages: [], subtitle: '', blocked: false,
      cancel: jest.fn(), send: jest.fn(), session: { sendClientEvent: jest.fn(), queueClientEvent: jest.fn(), queueCrisisPath: jest.fn(), inputFocused: jest.fn() },
    });
    await db.users.clear();
  });

  it('loads the female VRM for Aisha and retains it after route remount', async () => {
    await db.users.add({ id: 1, uid: 'uid-a', companion: 'aisha', avatar: 'female_human' });
    const first = render(<CompanionPage />);
    await waitFor(() => expect(screen.getByTestId('scene')).toHaveAttribute('data-model', '/models/koi-female.vrm'));
    expect(screen.getByTestId('scene')).toHaveAttribute('data-name', 'Aisha');
    first.unmount();
    render(<CompanionPage />);
    await waitFor(() => expect(screen.getByTestId('scene')).toHaveAttribute('data-model', '/models/koi-female.vrm'));
  });

  it('loads the male VRM for Raza and preserves the fox choice without substituting male', async () => {
    await db.users.add({ id: 2, uid: 'uid-a', companion: 'raza', avatar: 'male_human' });
    const view = render(<CompanionPage />);
    await waitFor(() => expect(screen.getByTestId('scene')).toHaveAttribute('data-model', '/models/koi-male.vrm'));
    view.unmount();
    await db.users.put({ id: 2, uid: 'uid-a', companion: 'koi', avatar: 'fox' });
    render(<CompanionPage />);
    await waitFor(() => expect(screen.getByTestId('scene')).toHaveTextContent(/fox choice is preserved/i));
    expect(screen.getByTestId('scene')).toHaveAttribute('data-model', '');
    expect(screen.getByTestId('scene')).toHaveTextContent(/fox choice is preserved/i);
  });

  it('isolates preference reads by UID and shows unavailable state on missing profile', async () => {
    await db.users.add({ id: 1, uid: 'uid-other', companion: 'aisha', avatar: 'female_human' });
    render(<CompanionPage />);
    await waitFor(() => expect(screen.getByTestId('scene')).toHaveTextContent(/could not be loaded/i));
    expect(screen.getByTestId('scene')).toHaveAttribute('data-model', '');
    expect(screen.getByTestId('scene')).toHaveTextContent(/could not be loaded/i);
  });

  it('keeps text/session available after model failure and retries the selected female model', async () => {
    await db.users.add({ id: 1, uid: 'uid-a', companion: 'aisha' });
    render(<CompanionPage />);
    await waitFor(() => expect(screen.getByTestId('scene')).toHaveAttribute('data-avatar-enabled', 'true'));
    fireEvent.click(screen.getByText('Simulate model failure'));
    expect(screen.getByTestId('scene')).toHaveAttribute('data-avatar-enabled', 'false');
    fireEvent.click(screen.getByRole('button', { name: 'Retry avatar' }));
    expect(screen.getByTestId('scene')).toHaveAttribute('data-avatar-enabled', 'true');
    expect(screen.getByTestId('scene')).toHaveAttribute('data-model', '/models/koi-female.vrm');
    expect(mockUseChat().cancel).not.toHaveBeenCalled();
  });

  it('passes existing session emotion/intensity transitions without changing the chat session', async () => {
    await db.users.add({ id: 1, uid: 'uid-a', companion: 'raza' });
    const chat = mockUseChat();
    const view = render(<CompanionPage />);
    await waitFor(() => expect(screen.getByTestId('scene')).toHaveAttribute('data-model', '/models/koi-male.vrm'));
    for (const emotion of ['joy', 'angry', 'sorrow', 'fun', 'neutral']) {
      mockUseChat.mockReturnValue({ ...chat, currentEmotion: emotion, currentIntensity: emotion === 'neutral' ? 0 : 0.7 });
      view.rerender(<CompanionPage />);
      expect(screen.getByTestId('scene')).toHaveAttribute('data-emotion', emotion);
      expect(screen.getByTestId('scene')).toHaveAttribute('data-intensity', emotion === 'neutral' ? '0' : '0.7');
    }
    expect(chat.cancel).not.toHaveBeenCalled();
  });
});
