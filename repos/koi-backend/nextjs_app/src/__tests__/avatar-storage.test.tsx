import React from 'react';
import { act, render, screen, waitFor } from '@testing-library/react';
jest.mock('dexie', () => jest.requireActual('../../node_modules/dexie/dist/dexie.js'));
import { db } from '@/lib/db';
import { loadAvatarPreference, saveAvatarPreference } from '@/lib/avatar/avatarPreference';
import { useAvatarPreference } from '@/hooks/useAvatarPreference';

function Preview({ uid }: { uid?: string }) {
  const state = useAvatarPreference(uid, false);
  return <p data-testid="selection">{state.status === 'ready' ? state.preference.status === 'selected' ? state.preference.companion : 'unselected' : state.status}</p>;
}

beforeEach(async () => { await db.users.clear(); });

it('persists explicit choices across IndexedDB reopen without changing other fields or accounts', async () => {
  await db.users.add({ uid: 'a', avatar: 'female_human', language: 'ur', createdAt: 'original' });
  await db.users.add({ uid: 'b', companion: 'koi', avatar: 'fox' });
  await saveAvatarPreference('a', 'raza');
  db.close(); await db.open();
  expect(await loadAvatarPreference('a')).toMatchObject({ companion: 'raza', avatar: 'male_human' });
  expect(await loadAvatarPreference('b')).toMatchObject({ companion: 'koi', avatar: 'fox' });
  expect(await db.users.where('uid').equals('a').first()).toMatchObject({ language: 'ur', createdAt: 'original' });
  expect(await db.users.count()).toBe(2);
});

it('serializes repeated saves without duplicate UID profiles and rejects invalid inputs without writes', async () => {
  await Promise.all([saveAvatarPreference('a', 'aisha'), saveAvatarPreference('a', 'aisha')]);
  const before = await db.users.toArray();
  await expect(saveAvatarPreference('', 'raza')).rejects.toThrow();
  await expect(saveAvatarPreference('a', 'unknown' as 'raza')).rejects.toThrow();
  expect(await db.users.toArray()).toEqual(before);
  expect(before).toHaveLength(1);
});

it('notifies both mounted preference consumers only after a successful save and hides previous owners', async () => {
  await saveAvatarPreference('a', 'aisha');
  await saveAvatarPreference('b', 'koi');
  function Both({ uid }: { uid?: string }) { return <><Preview uid={uid} /><Preview uid={uid} /></>; }
  const view = render(<Both uid="a" />);
  await waitFor(() => expect(screen.getAllByTestId('selection').every(el => el.textContent === 'aisha')).toBe(true));
  await act(async () => { await saveAvatarPreference('a', 'raza'); });
  await waitFor(() => expect(screen.getAllByTestId('selection').every(el => el.textContent === 'raza')).toBe(true));
  view.rerender(<Both uid="b" />);
  expect(screen.queryByText('raza')).not.toBeInTheDocument();
  await waitFor(() => expect(screen.getAllByTestId('selection').every(el => el.textContent === 'koi')).toBe(true));
  view.rerender(<Both />);
  expect(screen.queryByText('koi')).not.toBeInTheDocument();
});

it('preserves legacy mismatches and fox preferences while resolving without migrations', async () => {
  await db.users.add({ uid: 'a', companion: 'aisha', avatar: 'fox' });
  const before = await db.users.toArray();
  expect(await loadAvatarPreference('a')).toMatchObject({ avatar: 'female_human' });
  expect(await db.users.toArray()).toEqual(before);
});
