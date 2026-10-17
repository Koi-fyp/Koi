import React from 'react';
import { act, render, screen, waitFor } from '@testing-library/react';
jest.mock('dexie', () => jest.requireActual('../../node_modules/dexie/dist/dexie.js'));
import { db } from '@/lib/db';
import { loadUserPreferences, saveUserPreferences, reminderStatus } from '@/lib/preferences/userPreferences';
import { saveAvatarPreference, resolveAvatarPreference } from '@/lib/avatar/avatarPreference';
import { useUserPreferences } from '@/hooks/useUserPreferences';
beforeEach(async () => { await db.users.clear(); });
afterEach(() => jest.restoreAllMocks());
it('preserves existing profile fields and isolates language, time, enabled and nickname across reopen', async () => {
  await db.users.add({ uid: 'a', companion: 'aisha', avatar: 'female_human', createdAt: 'original' });
  await saveUserPreferences('a', { language: 'ur', notificationsEnabled: false, notificationTime: '18:45' });
  await saveAvatarPreference('a', 'aisha', 'Local companion');
  await saveAvatarPreference('b', 'koi');
  db.close(); await db.open();
  expect(await loadUserPreferences('a')).toMatchObject({ language: 'ur', notificationsEnabled: false, notificationTime: '18:45', displayName: 'Local companion', createdAt: 'original' });
  expect(resolveAvatarPreference(await loadUserPreferences('a'))).toMatchObject({ imageSrc: '/Female.png', displayName: 'Local companion' });
  expect(await loadUserPreferences('b')).toMatchObject({ avatar: 'fox' });
  expect((await loadUserPreferences('b'))?.displayName).toBeUndefined();
});
it.each([{ notificationTime: '25:00' }, { language: 'xx' }, { displayName: 'x'.repeat(65) }, { uid: 'other' }, { companion: 'aisha', avatar: 'male_human' }])('rejects invalid changes before writing: %j', async fields => {
  await expect(saveUserPreferences('a', fields as Parameters<typeof saveUserPreferences>[1])).rejects.toThrow();
  expect(await db.users.count()).toBe(0);
});
it('reports storage failure and never replaces a prior preference', async () => {
  await saveUserPreferences('a', { language: 'ur' });
  jest.spyOn(db.users, 'update').mockRejectedValueOnce(new Error('blocked'));
  await expect(saveUserPreferences('a', { language: 'en' })).rejects.toThrow();
  expect((await loadUserPreferences('a'))?.language).toBe('ur');
});
it('describes only device clock preference, never claims a delivered check-in', () => {
  const profile = { uid: 'a', notificationsEnabled: true, notificationTime: '18:00' };
  expect(reminderStatus(profile, new Date(2026, 9, 17, 19))).toContain('Preferred time reached');
  expect(reminderStatus(profile, new Date(2026, 9, 17, 12))).toContain('later today');
  expect(reminderStatus(profile, new Date(2026, 9, 17, 19))).toContain('No message is scheduled');
  expect(reminderStatus(null, new Date())).toContain('No check-in preference');
});
it('immediately hides old owner fields on switch/logout and offers a recoverable error', async () => {
  await saveUserPreferences('a', { displayName: 'A-only' });
  function View({ uid }: { uid?: string }) {
    const { state, retry } = useUserPreferences(uid);
    return <div><p>{state.status === 'ready' ? state.profile?.displayName ?? 'No profile' : state.status}</p><button onClick={retry}>Retry</button></div>;
  }
  const view = render(<View uid="a" />);
  await screen.findByText('A-only');
  view.rerender(<View uid="b" />);
  expect(screen.queryByText('A-only')).not.toBeInTheDocument();
  await screen.findByText('No profile');
  view.rerender(<View />);
  await waitFor(() => expect(screen.getByText('No profile')).toBeInTheDocument());
});
