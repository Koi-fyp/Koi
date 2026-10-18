/** @jest-environment jsdom */
import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import OnboardingPage from '@/app/onboarding/page';
import { db } from '@/lib/db';
import { isOnboardingComplete, onboardingStorageKey, resolveOnboardingComplete } from '@/lib/onboarding';

const mockReplace = jest.fn();
const mockSetDoc = jest.fn().mockResolvedValue(undefined);
const mockAuthState = jest.fn();
jest.mock('next/navigation', () => ({ useRouter: () => ({ replace: mockReplace }) }));
let mockUid = 'uid-a';
jest.mock('@/lib/firebase', () => ({ auth: { get currentUser() { return { uid: mockUid }; } }, firestore: {} }));
jest.mock('@/contexts/AuthContext', () => ({ useAuth: () => mockAuthState() }));
jest.mock('firebase/firestore', () => ({ doc: jest.fn((...parts: unknown[]) => parts), setDoc: (...args: unknown[]) => mockSetDoc(...args) }));
jest.mock('next/image', () => ({ __esModule: true, default: (props: React.ImgHTMLAttributes<HTMLImageElement>) => <img {...props} /> }));

describe('onboarding companion selection application path', () => {
  beforeEach(async () => {
    mockUid = 'uid-a';
    mockAuthState.mockImplementation(() => ({ user: { uid: mockUid }, loading: false }));
    window.history.replaceState(null, '', '/onboarding');
    mockReplace.mockReset();
    mockSetDoc.mockReset().mockResolvedValue(undefined);
    localStorage.clear();
    await db.users.clear();
  });

  it('selects Aisha once and saves female_human against the signed-in UID', async () => {
    render(<OnboardingPage />);
    fireEvent.click(screen.getByRole('button', { name: 'Continue' }));
    fireEvent.click(screen.getByRole('button', { name: /I Understand/i }));
    fireEvent.click(await screen.findByRole('button', { name: /Aisha.*Female avatar/i }));
    expect(screen.getByRole('img', { name: 'Aisha avatar preview' })).toHaveAttribute('src', '/Female.png');
    fireEvent.click(screen.getByRole('button', { name: 'Continue with Aisha' }));
    fireEvent.click(screen.getByRole('checkbox', { name: /I understand KOI is an AI/i }));
    fireEvent.click(screen.getByRole('checkbox', { name: /I understand saved history is encrypted/i }));
    fireEvent.click(screen.getByRole('button', { name: /I Agree/i }));
    fireEvent.click(screen.getByRole('button', { name: /Continue/i }));
    fireEvent.click(screen.getByRole('button', { name: /Let's Go/i }));

    await waitFor(() => expect(mockReplace).toHaveBeenCalledWith('/chat'));
    const rows = await db.users.toArray();
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ uid: 'uid-a', companion: 'aisha', avatar: 'female_human', onboardingComplete: true });
    expect(mockSetDoc).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({
      profile: expect.objectContaining({ companion: 'aisha', avatar: 'female_human' }),
      onboarding_complete: true,
    }), { merge: true });
    expect(localStorage.getItem(onboardingStorageKey('uid-a'))).toBe('true');
    expect(localStorage.getItem('koi_onboarding_complete')).toBeNull();
  });

  it('retains Koi as the selected fox preference', async () => {
    render(<OnboardingPage initialStep={2} />);
    fireEvent.click(await screen.findByRole('button', { name: /Koi.*Fox choice/i }));
    fireEvent.click(screen.getByRole('button', { name: /Continue with Koi/i }));
    fireEvent.click(screen.getByRole('checkbox', { name: /I understand KOI is an AI/i }));
    fireEvent.click(screen.getByRole('checkbox', { name: /I understand saved history is encrypted/i }));
    fireEvent.click(screen.getByRole('button', { name: /I Agree/i }));
    fireEvent.click(screen.getByRole('button', { name: /Continue/i }));
    fireEvent.click(screen.getByRole('button', { name: /Let's Go/i }));
    await waitFor(() => expect(mockReplace).toHaveBeenCalledWith('/chat'));
    expect((await db.users.toArray())[0]).toMatchObject({ companion: 'koi', avatar: 'fox' });
  });

  it('shows local persistence failure and does not navigate as if saved', async () => {
    const users = db.users as unknown as { add: (record: unknown) => Promise<unknown> };
    const originalAdd = users.add;
    users.add = jest.fn().mockRejectedValue(new Error('storage unavailable'));
    render(<OnboardingPage initialStep={5} />);
    await waitFor(() => expect(screen.getByRole('button', { name: /Let's Go/i })).not.toBeDisabled());
    fireEvent.click(screen.getByRole('button', { name: /Let's Go/i }));
    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent(/could not be saved on this device/i));
    expect(mockReplace).not.toHaveBeenCalled();
    users.add = originalAdd;
  });

  it('shows Firestore sync failure while retaining the local choice and not navigating', async () => {
    mockSetDoc.mockRejectedValueOnce(new Error('offline'));
    render(<OnboardingPage initialStep={5} />);
    await waitFor(() => expect(screen.getByRole('button', { name: /Let's Go/i })).not.toBeDisabled());
    fireEvent.click(screen.getByRole('button', { name: /Let's Go/i }));
    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent(/saved on this device, but could not sync/i));
    expect((await db.users.toArray())[0]).toMatchObject({ uid: 'uid-a', avatar: 'male_human' });
    expect(mockReplace).not.toHaveBeenCalled();
    // The local save is the receipt: a cloud failure must not send this UID back through setup.
    expect(localStorage.getItem(onboardingStorageKey('uid-a'))).toBe('true');
    expect(await resolveOnboardingComplete('uid-a')).toBe(true);
  });

  it('restores an existing avatar-only legacy choice instead of preselecting Koi or rewriting it', async () => {
    await db.users.add({ id: 7, uid: 'uid-a', avatar: 'female_human', language: 'ur' });
    render(<OnboardingPage initialStep={2} />);
    const aisha = await screen.findByRole('button', { name: /Aisha.*Female avatar/i });
    expect(aisha).toHaveAttribute('aria-pressed', 'true');
    expect((await db.users.get(7))?.companion).toBeUndefined();
    expect((await db.users.get(7))?.language).toBe('ur');
  });

  it('renders safely while authentication is loading and after sign-out, without an implicit selection write', () => {
    mockAuthState.mockReturnValue({ user: null, loading: true });
    const view = render(<OnboardingPage initialStep={2} />);
    expect(screen.getByRole('status')).toHaveTextContent('Loading your saved companion');
    mockAuthState.mockReturnValue({ user: null, loading: false });
    view.rerender(<OnboardingPage key="signed-out" initialStep={5} />);
    expect(screen.getByRole('button', { name: /Let's Go/i })).toBeDisabled();
    expect(mockSetDoc).not.toHaveBeenCalled();
  });

  it('offers explicit local continuation during pending sync without duplicate writes or false cloud success', async () => {
    mockSetDoc.mockImplementation(() => new Promise(() => {}));
    await db.users.add({ id: 4, uid: 'uid-a', companion: 'aisha', avatar: 'female_human' });
    render(<OnboardingPage initialStep={5} />);
    await waitFor(() => expect(screen.getByRole('button', { name: /Let's Go/i })).not.toBeDisabled());
    const save = screen.getByRole('button', { name: /Let's Go/i });
    fireEvent.click(save);
    expect(await screen.findByRole('link', { name: 'Continue with saved companion' })).toHaveAttribute('href', '/chat');
    expect(screen.getByRole('button', { name: 'Saving companion...' })).toBeDisabled();
    expect((await db.users.get(4))?.avatar).toBe('female_human');
    expect(mockSetDoc).toHaveBeenCalledTimes(1);
    expect(mockReplace).not.toHaveBeenCalled();
    expect(isOnboardingComplete('uid-a')).toBe(true);
  });
});

describe('per-UID onboarding completion', () => {
  beforeEach(async () => {
    mockUid = 'uid-a';
    mockAuthState.mockImplementation(() => ({ user: { uid: mockUid }, loading: false }));
    mockReplace.mockReset();
    mockSetDoc.mockReset().mockResolvedValue(undefined);
    localStorage.clear();
    window.history.replaceState(null, '', '/onboarding');
    await db.users.clear();
  });

  it('a second UID in the same browser still sees onboarding', async () => {
    render(<OnboardingPage initialStep={5} />);
    await waitFor(() => expect(screen.getByRole('button', { name: /Let's Go/i })).not.toBeDisabled());
    fireEvent.click(screen.getByRole('button', { name: /Let's Go/i }));
    await waitFor(() => expect(mockReplace).toHaveBeenCalledWith('/chat'));
    mockUid = 'uid-b'; mockReplace.mockReset();
    expect(isOnboardingComplete('uid-b')).toBe(false);
    expect(await resolveOnboardingComplete('uid-b')).toBe(false);
    render(<OnboardingPage key="uid-b" />);
    expect(await screen.findByRole('button', { name: 'Continue' })).toBeInTheDocument();
    await new Promise(resolve => setTimeout(resolve, 0));
    expect(mockReplace).not.toHaveBeenCalled();
  });

  it('migrates the legacy global flag only for the signed-in owner of a completed local row', async () => {
    localStorage.setItem('koi_onboarding_complete', 'true');
    await db.users.add({ id: 1, uid: 'uid-a', onboardingComplete: true });
    mockUid = 'uid-b';
    expect(await resolveOnboardingComplete('uid-b')).toBe(false);
    expect(await resolveOnboardingComplete('uid-a')).toBe(false); // not the signed-in user
    await db.users.add({ id: 2, uid: 'uid-c', onboardingComplete: false });
    mockUid = 'uid-c';
    expect(await resolveOnboardingComplete('uid-c')).toBe(false);
    mockUid = 'uid-a';
    expect(await resolveOnboardingComplete('uid-a')).toBe(true);
    expect(localStorage.getItem(onboardingStorageKey('uid-a'))).toBe('true');
  });

  it('redirects an onboarded UID to chat; Redo setup is explicit and keeps the saved row', async () => {
    await db.users.add({ id: 9, uid: 'uid-a', companion: 'aisha', avatar: 'female_human', language: 'ur', onboardingComplete: true, createdAt: '2026-01-01T00:00:00.000Z' });
    localStorage.setItem(onboardingStorageKey('uid-a'), 'true');
    const first = render(<OnboardingPage />);
    await waitFor(() => expect(mockReplace).toHaveBeenCalledWith('/chat'));
    expect(screen.queryByRole('button', { name: 'Continue' })).toBeNull();
    first.unmount(); mockReplace.mockReset();
    window.history.replaceState(null, '', '/onboarding?redo=1');
    render(<OnboardingPage initialStep={5} />);
    await waitFor(() => expect(screen.getByRole('button', { name: /Let's Go/i })).not.toBeDisabled());
    expect(mockReplace).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole('button', { name: /Let's Go/i }));
    await waitFor(() => expect(mockReplace).toHaveBeenCalledWith('/chat'));
    expect(await db.users.toArray()).toEqual([expect.objectContaining({ id: 9, companion: 'aisha', language: 'ur', createdAt: '2026-01-01T00:00:00.000Z', onboardingComplete: true })]);
  });
});
