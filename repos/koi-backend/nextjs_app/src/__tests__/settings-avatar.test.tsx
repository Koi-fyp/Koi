import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
jest.mock('dexie', () => jest.requireActual('../../node_modules/dexie/dist/dexie.js'));
jest.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: { uid: 'owner' }, loading: false }) }));
jest.mock('@/app/(authenticated)/settings/components/Toast', () => ({ __esModule: true, default: ({ message }: { message: string }) => <p role="status">{message}</p> }));
jest.mock('@/app/(authenticated)/settings/components/AvatarPicker', () => ({ __esModule: true,
  default: ({ isOpen, currentAvatar, onSave }: { isOpen: boolean; currentAvatar: string; onSave: (id: string, name: string) => Promise<boolean> }) => isOpen
    ? <div><p data-testid="initial-choice">{currentAvatar}</p><button onClick={() => void onSave('raza', '')}>Save Raza fixture</button></div> : null,
}));
import SettingsPage from '@/app/(authenticated)/settings/page';
import { db } from '@/lib/db';

beforeEach(async () => {
  await db.users.clear();
  await db.users.add({ uid: 'owner', companion: 'aisha', avatar: 'female_human', language: 'ur' });
  await db.users.add({ uid: 'other', companion: 'koi', avatar: 'fox' });
});
afterEach(() => jest.restoreAllMocks());

it('restores Settings selection and saves through the same UID-scoped source used by both screens', async () => {
  render(<SettingsPage />);
  await screen.findByText('Aisha 👩');
  fireEvent.click(screen.getByText('Avatar & Name'));
  expect(screen.getByTestId('initial-choice')).toHaveTextContent('aisha');
  fireEvent.click(screen.getByText('Save Raza fixture'));
  await screen.findByText('Companion saved on this device.');
  await screen.findByText('Raza 👨');
  expect(await db.users.where('uid').equals('owner').first()).toMatchObject({ companion: 'raza', avatar: 'male_human', language: 'ur' });
  expect(await db.users.where('uid').equals('other').first()).toMatchObject({ companion: 'koi', avatar: 'fox' });
});

it('does not report success or change a saved selection when storage rejects the update', async () => {
  render(<SettingsPage />);
  await screen.findByText('Aisha 👩');
  jest.spyOn(db.users, 'update').mockRejectedValueOnce(new Error('Synthetic storage failure'));
  fireEvent.click(screen.getByText('Avatar & Name'));
  fireEvent.click(screen.getByText('Save Raza fixture'));
  await waitFor(() => expect(screen.getByText(/Companion could not be saved/)).toBeInTheDocument());
  expect(await db.users.where('uid').equals('owner').first()).toMatchObject({ companion: 'aisha', avatar: 'female_human' });
});

it('disables unapproved deletion and replaces invented storage and release claims', async () => {
  const { container } = render(<SettingsPage />);
  await screen.findByText('Browser Storage Estimate');
  expect(screen.getByRole('button', { name: /Clear History/ })).toBeDisabled();
  expect(container.textContent).not.toMatch(/42 KB|5 MB used|January 2025|24\/7 helplines|v1\.0\.0/);
  expect(screen.getByText(/Browser storage estimate unavailable/)).toBeInTheDocument();
});
