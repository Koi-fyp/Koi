import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
const mockReplace = jest.fn();
const mockPush = jest.fn();
const mockAuth = jest.fn();
const mockResolve = jest.fn();
jest.mock('@/contexts/AuthContext', () => ({ useAuth: () => mockAuth() }));
jest.mock('next/navigation', () => ({ useRouter: () => ({ replace: mockReplace, push: mockPush }) }));
jest.mock('@/lib/firebase', () => ({ FirebaseConfigurationError: class extends Error {} }));
jest.mock('@/lib/onboarding', () => ({ isOnboardingComplete: () => false, resolveOnboardingComplete: (uid: string) => mockResolve(uid) }));
import Landing from '@/app/page';

const signedIn = { user: { uid: 'fixture-owner' }, loading: false, error: null, signInAnonymously: jest.fn() };
const HERO = /Your\s+mind\s+deserves a\s+friend\./;

beforeAll(() => { global.IntersectionObserver = class { observe() {} unobserve() {} disconnect() {} } as unknown as typeof IntersectionObserver; });
beforeEach(() => {
  mockReplace.mockReset(); mockPush.mockReset(); mockResolve.mockReset();
  window.history.replaceState(null, '', '/');
});

it('shows only the neutral spinner while auth is unresolved', () => {
  mockAuth.mockReturnValue({ user: null, loading: true, error: null, signInAnonymously: jest.fn() });
  render(<Landing />);
  expect(screen.getByTestId('auth-pending-spinner')).toBeInTheDocument();
  expect(screen.queryByRole('heading', { level: 1 })).toBeNull();
  expect(mockReplace).not.toHaveBeenCalled();
});

it('renders the landing page with the sign-in CTA when signed out', () => {
  mockAuth.mockReturnValue({ user: null, loading: false, error: null, signInAnonymously: jest.fn() });
  render(<Landing />);
  expect(screen.getByRole('heading', { level: 1, name: HERO })).toBeInTheDocument();
  expect(screen.getByRole('button', { name: /Get Started/ })).toBeInTheDocument();
  expect(screen.queryByTestId('auth-pending-spinner')).toBeNull();
  expect(mockReplace).not.toHaveBeenCalled();
});

it('replaces / with /chat for a signed-in, onboarded user without ever rendering the landing', async () => {
  mockAuth.mockReturnValue(signedIn);
  mockResolve.mockResolvedValue(true);
  render(<Landing />);
  expect(screen.queryByRole('heading', { level: 1 })).toBeNull();
  expect(screen.getByTestId('auth-pending-spinner')).toBeInTheDocument();
  await waitFor(() => expect(mockReplace).toHaveBeenCalledWith('/chat'));
  expect(mockResolve).toHaveBeenCalledWith('fixture-owner');
  expect(mockPush).not.toHaveBeenCalled();
  expect(screen.queryByRole('heading', { level: 1 })).toBeNull();
});

it('replaces / with /onboarding for a signed-in user who has not onboarded', async () => {
  mockAuth.mockReturnValue(signedIn);
  mockResolve.mockResolvedValue(false);
  render(<Landing />);
  await waitFor(() => expect(mockReplace).toHaveBeenCalledWith('/onboarding'));
  expect(screen.queryByRole('heading', { level: 1 })).toBeNull();
});

it('keeps a signed-in user on the landing page for /?home=1 and offers Open chat', async () => {
  window.history.replaceState(null, '', '/?home=1');
  mockAuth.mockReturnValue(signedIn);
  mockResolve.mockResolvedValue(true);
  render(<Landing />);
  expect(await screen.findByRole('heading', { level: 1, name: HERO })).toBeInTheDocument();
  expect(screen.queryByRole('button', { name: /Get Started/ })).toBeNull();
  const open = screen.getByRole('button', { name: 'Open chat' });
  expect(open).toHaveClass('neo-btn-primary');
  fireEvent.click(open);
  await waitFor(() => expect(mockPush).toHaveBeenCalledWith('/chat'));
  expect(mockReplace).not.toHaveBeenCalled();
});
