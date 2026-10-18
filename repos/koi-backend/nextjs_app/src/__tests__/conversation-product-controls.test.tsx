import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
const mockSave = jest.fn();
let mockUid = 'synthetic-owner';
jest.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: { uid: mockUid }, loading: false }) }));
jest.mock('@/lib/firebase', () => ({ auth: { get currentUser() { return { uid: mockUid }; } } }));
jest.mock('@/hooks/useAvatarPreference', () => ({ useAvatarPreference: () => ({ status: 'ready', preference: { status: 'selected', companion: 'koi', name: 'Koi' } }) }));
jest.mock('@/lib/avatar/avatarPreference', () => ({ saveAvatarPreference: (...args: unknown[]) => mockSave(...args) }));
jest.mock('@/app/(authenticated)/settings/components/AvatarPicker', () => ({ __esModule: true, default: ({ onSave, currentAvatar }: { onSave: (id: string, name: string) => Promise<boolean>; currentAvatar: string }) => <button onClick={() => void onSave('raza', 'Raza')}>Save {currentAvatar} as Raza</button> }));
import ProductControls from '@/components/chat/ConversationProductControls';
function Controls() { return <ProductControls preferenceState={{ status: 'ready', uid: mockUid, profile: null, preference: { status: 'selected', companion: 'koi', avatar: 'fox', name: 'Koi', imageSrc: null, modelUrl: null } }} />; }
beforeEach(() => { mockUid = 'synthetic-owner'; mockSave.mockReset().mockResolvedValue(undefined); });
it('exposes New Chat without pretending protected switching or completion works', () => {
  render(<Controls />); expect(screen.getByRole('button', { name: 'New Chat' })).toBeDisabled();
  fireEvent.click(screen.getByRole('button', { name: 'Complete Conversation' }));
  expect(screen.getByRole('button', { name: /Save completion/ })).toBeDisabled(); expect(mockSave).not.toHaveBeenCalled();
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
