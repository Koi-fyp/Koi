import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
const mockSave = jest.fn();
let mockUid = 'synthetic-owner';
jest.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: { uid: mockUid }, loading: false }) }));
jest.mock('@/lib/firebase', () => ({ auth: { get currentUser() { return { uid: mockUid }; } } }));
jest.mock('@/hooks/useAvatarPreference', () => ({ useAvatarPreference: () => ({ status: 'ready', preference: { status: 'selected', companion: 'koi', name: 'Koi' } }) }));
jest.mock('@/lib/avatar/avatarPreference', () => ({ saveAvatarPreference: (...args: unknown[]) => mockSave(...args) }));
jest.mock('@/app/(authenticated)/settings/components/AvatarPicker', () => ({ __esModule: true, default: ({ onSave, currentAvatar }: { onSave: (id: string, name: string) => Promise<boolean>; currentAvatar: string }) => <button onClick={() => void onSave('raza', 'Raza')}>Save {currentAvatar} as Raza</button> }));
const mockComplete = jest.fn();
const mockCreate = jest.fn();
let mockRecovery = { loading: false, error: null as string | null, completing: false, switching: false, hasQualifyingPair: false, hasUnresolvedHandoff: false };
const mockManager = { uid: 'synthetic-owner', subscribe: () => () => {}, getSnapshot: () => mockRecovery };
jest.mock('@/contexts/ConversationContext', () => ({ useSharedConversation: () => mockManager, useOwnedConversationActions: () => ({ createOwned: (...args: unknown[]) => mockCreate(...args), openOwned: jest.fn() }) }));
jest.mock('@/lib/activities/conversationCompletion', () => ({ saveConversationCompletion: (...args: unknown[]) => mockComplete(...args) }));
import ProductControls from '@/components/chat/ConversationProductControls';
function Controls({ pending = false }: { pending?: boolean }) { return <ProductControls pending={pending} preferenceState={{ status: 'ready', uid: mockUid, profile: null, preference: { status: 'selected', companion: 'koi', avatar: 'fox', name: 'Koi', imageSrc: null, modelUrl: null } }} />; }
beforeEach(() => {
  mockUid = 'synthetic-owner'; mockSave.mockReset().mockResolvedValue(undefined);
  mockComplete.mockReset().mockResolvedValue({ status: 'saved', outcome: 'awarded', completionId: 'c' });
  mockCreate.mockReset().mockResolvedValue({ conversationId: 'next', previousConversationId: 'prev' });
  mockRecovery = { loading: false, error: null, completing: false, switching: false, hasQualifyingPair: false, hasUnresolvedHandoff: false };
});
it('keeps Save completion disabled without a saved pair, while pending, or with an open handoff', () => {
  const view = render(<Controls />);
  fireEvent.click(screen.getByRole('button', { name: 'Complete Conversation' }));
  expect(screen.getByRole('button', { name: /Save completion/ })).toBeDisabled();
  mockRecovery = { ...mockRecovery, hasQualifyingPair: true, hasUnresolvedHandoff: true }; view.rerender(<Controls />);
  expect(screen.getByRole('button', { name: /Save completion/ })).toBeDisabled();
  expect(screen.getByRole('region')).toHaveTextContent(/crisis support step is still open/);
  mockRecovery = { ...mockRecovery, hasUnresolvedHandoff: false };
  view.rerender(<Controls pending />);
  expect(screen.getByRole('button', { name: /Save completion/ })).toBeDisabled();
  expect(mockComplete).not.toHaveBeenCalled(); expect(mockSave).not.toHaveBeenCalled();
});
it('saves completion only on the explicit click and reports the real ledger outcome', async () => {
  mockRecovery = { ...mockRecovery, hasQualifyingPair: true };
  render(<Controls />);
  expect(mockComplete).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole('button', { name: 'Complete Conversation' }));
  expect(mockComplete).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole('button', { name: 'Save completion' }));
  expect(await screen.findByRole('status')).toHaveTextContent('One piece was added');
  expect(mockComplete).toHaveBeenCalledTimes(1); expect(mockComplete).toHaveBeenCalledWith(mockManager, 'synthetic-owner');
  mockComplete.mockResolvedValue({ status: 'saved', outcome: 'daily-cap', completionId: 'd' });
  fireEvent.click(screen.getByRole('button', { name: 'Save completion' }));
  expect(await screen.findByText(/already earned, so no new piece/)).toBeInTheDocument();
});
it('New Chat is enabled when idle, says reply in progress while pending, and never completes the conversation', async () => {
  mockRecovery = { ...mockRecovery, hasQualifyingPair: true };
  const view = render(<Controls pending />);
  expect(screen.getByRole('button', { name: 'New Chat (reply in progress)' })).toBeDisabled();
  view.rerender(<Controls />);
  fireEvent.click(screen.getByRole('button', { name: 'New Chat' }));
  await waitFor(() => expect(mockCreate).toHaveBeenCalledTimes(1));
  expect(mockComplete).not.toHaveBeenCalled();
});
it('reports a refused New Chat without claiming a new conversation', async () => {
  const { ConversationSwitchError } = jest.requireActual('@/lib/conversation/PersistentConversation');
  mockCreate.mockRejectedValue(new ConversationSwitchError('conflict'));
  render(<Controls />); fireEvent.click(screen.getByRole('button', { name: 'New Chat' }));
  expect(await screen.findByRole('alert')).toHaveTextContent('changed in another tab');
});
it('preserves fox until explicit selection and saves only through existing UID preference writer', async () => {
  render(<Controls />); expect(mockSave).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole('button', { name: 'Change companion' }));
  fireEvent.click(screen.getByRole('button', { name: 'Save koi as Raza' }));
  await waitFor(() => expect(mockSave).toHaveBeenCalledWith('synthetic-owner', 'raza', 'Raza'));
});
it('reports failed saves without success claims', async () => {
  mockSave.mockRejectedValue(new Error('synthetic denied'));
  render(<Controls />); fireEvent.click(screen.getByRole('button', { name: 'Change companion' }));
  fireEvent.click(screen.getByRole('button', { name: /Save koi/ })); expect(await screen.findByRole('alert')).toHaveTextContent('could not be saved');
});
it('closes the previous owner picker immediately on account change', () => {
  const view = render(<Controls />); fireEvent.click(screen.getByRole('button', { name: 'Change companion' }));
  mockUid = 'other-synthetic-owner'; view.rerender(<Controls />); expect(screen.queryByText('Save koi as Raza')).not.toBeInTheDocument();
});
