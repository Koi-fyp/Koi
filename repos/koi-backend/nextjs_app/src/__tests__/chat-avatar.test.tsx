/** @jest-environment jsdom */
import React from 'react';
import { act, fireEvent, render, waitFor } from '@testing-library/react';

const mockUseAuth = jest.fn();
const mockUseChat = jest.fn();
const mockProfileFirst = jest.fn();

jest.mock('@/contexts/AuthContext', () => ({ useAuth: () => mockUseAuth() }));
jest.mock('@/hooks/useChat', () => ({ useChat: () => mockUseChat() }));
jest.mock('@/contexts/ConversationContext', () => { const snapshot = { loading: false, error: null, completing: false, switching: false, hasQualifyingPair: false, hasUnresolvedHandoff: false }; const manager = { uid: 'fixture', session: null, subscribe: () => () => {}, getSnapshot: () => snapshot }; return { useSharedConversation: () => manager, useOwnedConversationActions: () => ({ createOwned: async () => ({}), openOwned: async () => ({}) }) }; });
jest.mock('@/lib/db', () => ({ db: { users: { where: () => ({ equals: () => ({ first: mockProfileFirst }) }) } } }));
jest.mock('@/components/chat/MessageList', () => ({ __esModule: true, default: () => <div role="log" /> }));
jest.mock('@/components/chat/InputBar', () => ({ __esModule: true, default: () => <div data-testid="composer" /> }));
jest.mock('next/image', () => ({
  __esModule: true,
  default: ({ priority: _priority, sizes: _sizes, ...props }: React.ImgHTMLAttributes<HTMLImageElement> & { priority?: boolean; sizes?: string }) => require('react').createElement('img', props),
}));

import ChatPage from '@/app/(authenticated)/chat/page';

describe('authenticated chat avatar preview', () => {
  beforeEach(() => {
    mockUseAuth.mockReturnValue({ user: { uid: 'test-user' }, loading: false });
    mockUseChat.mockReturnValue({ messages: [], isTyping: false, send: jest.fn(), error: null, blocked: false });
    mockProfileFirst.mockResolvedValue({ avatar: 'male_human' });
  });

  it('uses the saved female preference and keeps the avatar visible with conversation messages', async () => {
    mockProfileFirst.mockResolvedValueOnce({ avatar: 'female_human' });
    mockUseChat.mockReturnValueOnce({
      messages: [{ id: 'm1', sender: 'user', content: 'Hello' }], isTyping: false, send: jest.fn(), error: null, blocked: false,
    });
    const view = render(<ChatPage />);

    const panel = view.getByTestId('chat-avatar-panel');
    expect(panel).toBeInTheDocument();
    expect(panel.className).not.toMatch(/hidden/);
    const responsiveStyles = Array.from(document.querySelectorAll('style')).map((style) => style.textContent).join('\n');
    expect(responsiveStyles).toContain('flex-direction: column-reverse');
    expect(responsiveStyles).toContain('@media (min-width: 640px)');
    expect(responsiveStyles).toContain('clamp(132px, 29svh, 230px)');
    await waitFor(() => expect(view.getByRole('img').getAttribute('src')).toContain('Female.png'));
    expect(view.getByRole('link', { name: 'Open avatar conversation' })).toHaveAttribute('href', '/companion-scene');
    expect(view.getByTestId('composer')).toBeInTheDocument();
  });

  it('uses the male PNG for Raza, reacts to a preference change, and retains it after remount', async () => {
    let savedProfile = { avatar: 'male_human', companion: 'raza' };
    mockProfileFirst.mockImplementation(() => Promise.resolve(savedProfile));
    const first = render(<ChatPage />);
    await waitFor(() => expect(first.getByRole('img')).toHaveAttribute('src', '/Male.png'));
    savedProfile = { avatar: 'female_human', companion: 'aisha' };
    act(() => window.dispatchEvent(new CustomEvent('koi-avatar-preference-changed', { detail: { uid: 'test-user' } })));
    await waitFor(() => expect(first.getByRole('img')).toHaveAttribute('src', '/Female.png'));
    first.unmount();
    const second = render(<ChatPage />);
    await waitFor(() => expect(second.getByRole('img')).toHaveAttribute('src', '/Female.png'));
  });

  it('preserves the legacy fox choice without substituting a different avatar', async () => {
    mockProfileFirst.mockResolvedValueOnce({ avatar: 'fox' });
    const view = render(<ChatPage />);
    await waitFor(() => expect(view.getByRole('status')).toHaveTextContent(/Koi fox choice is preserved/i));
    expect(view.queryByRole('img')).not.toBeInTheDocument();
    expect(view.getByRole('link', { name: 'Open the 3D avatar conversation' })).toHaveAttribute('href', '/companion-scene');
  });

  it('shows a clear choice prompt rather than guessing the male asset for missing data', async () => {
    mockProfileFirst.mockResolvedValueOnce(undefined);
    const view = render(<ChatPage />);
    await waitFor(() => expect(view.getByRole('status')).toHaveTextContent(/no companion avatar is saved/i));
    expect(view.queryByRole('img')).not.toBeInTheDocument();
  });

  it('shows a preference read error without substituting a male image', async () => {
    mockProfileFirst.mockRejectedValueOnce(new Error('IndexedDB unavailable'));
    const view = render(<ChatPage />);
    await waitFor(() => expect(view.getByRole('status')).toHaveTextContent(/saved companion could not be loaded/i));
    expect(view.queryByRole('img')).not.toBeInTheDocument();
    expect(view.getByRole('link', { name: 'Review companion selection' })).toHaveAttribute('href', '/onboarding');
  });

  it('shows a non-blocking fallback and preserves the 3D conversation link when an image fails', async () => {
    const view = render(<ChatPage />);
    await waitFor(() => expect(view.getByRole('img')).toBeInTheDocument());
    fireEvent.error(view.getByRole('img'));
    expect(view.getByRole('status')).toHaveTextContent(/preview image could not be loaded/i);
    expect(view.getByRole('link', { name: 'Open the 3D avatar conversation' })).toHaveAttribute('href', '/companion-scene');
    expect(view.getByTestId('composer')).toBeInTheDocument();
  });
});
