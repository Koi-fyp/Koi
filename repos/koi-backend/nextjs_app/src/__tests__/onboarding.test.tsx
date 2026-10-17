/** @jest-environment jsdom */
import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import OnboardingPage from '@/app/onboarding/page';
import { db } from '@/lib/db';

const mockReplace = jest.fn();
const mockSetDoc = jest.fn().mockResolvedValue(undefined);
const mockAuthState = jest.fn();
jest.mock('next/navigation', () => ({ useRouter: () => ({ replace: mockReplace }) }));
jest.mock('@/lib/firebase', () => ({ auth: { currentUser: { uid: 'uid-a' } }, firestore: {} }));
jest.mock('@/contexts/AuthContext', () => ({ useAuth: () => mockAuthState() }));
jest.mock('firebase/firestore', () => ({ doc: jest.fn((...parts: unknown[]) => parts), setDoc: (...args: unknown[]) => mockSetDoc(...args) }));
jest.mock('next/image', () => ({ __esModule: true, default: (props: React.ImgHTMLAttributes<HTMLImageElement>) => <img {...props} /> }));

describe('onboarding companion selection application path', () => {
  beforeEach(async () => {
    mockAuthState.mockReturnValue({ user: { uid: 'uid-a' }, loading: false });
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
    fireEvent.click(screen.getByRole('checkbox', { name: /I agree to Privacy Policy/i }));
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
    expect(localStorage.getItem('koi_onboarding_complete')).toBe('true');
  });

  it('retains Koi as the selected fox preference', async () => {
    render(<OnboardingPage initialStep={2} />);
    fireEvent.click(await screen.findByRole('button', { name: /Koi.*Fox choice/i }));
    fireEvent.click(screen.getByRole('button', { name: /Continue with Koi/i }));
    fireEvent.click(screen.getByRole('checkbox', { name: /I understand KOI is an AI/i }));
    fireEvent.click(screen.getByRole('checkbox', { name: /I agree to Privacy Policy/i }));
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
    expect(localStorage.getItem('koi_onboarding_complete')).toBeNull();
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
    expect(localStorage.getItem('koi_onboarding_complete')).toBeNull();
  });
});
