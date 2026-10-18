import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
const mockSignIn = jest.fn();
const mockReplace = jest.fn();
const mockAuth = jest.fn();
jest.mock('@/contexts/AuthContext', () => ({ useAuth: () => mockAuth() }));
jest.mock('next/navigation', () => ({ useRouter: () => ({ replace: mockReplace }) }));
jest.mock('@/lib/firebase', () => ({ FirebaseConfigurationError: class extends Error {} }));
jest.mock('@/lib/onboarding', () => ({ isOnboardingComplete: () => false, resolveOnboardingComplete: async () => false }));
import Landing from '@/app/page';
import How from '@/app/how-it-works/page';
import Welcome from '@/components/onboarding/WelcomeStep';
beforeAll(() => { global.IntersectionObserver = class { observe() {} unobserve() {} disconnect() {} } as unknown as typeof IntersectionObserver; });
beforeEach(() => {
  mockReplace.mockReset(); mockSignIn.mockReset();
  mockAuth.mockReturnValue({ user: null, loading: false, error: new Error('Synthetic sign-in failure'), signInAnonymously: mockSignIn });
});
it.each([Landing, How])('allows retry after an auth-provider-reported failure without navigating', async Component => {
  mockSignIn.mockResolvedValue(undefined); // Existing provider reports errors in context, not by rejection.
  render(<Component />);
  const button = screen.getAllByRole('button', { name: /Get Started|Start Talking/ })[0];
  fireEvent.click(button);
  await waitFor(() => expect(button).not.toBeDisabled());
  fireEvent.click(button);
  await waitFor(() => expect(mockSignIn).toHaveBeenCalledTimes(2));
  expect(mockReplace).not.toHaveBeenCalled();
  expect(screen.getAllByRole('alert').length).toBeGreaterThan(0);
});
it('navigates from How It Works only after actual signed-in user state arrives', () => {
  const view = render(<How />);
  fireEvent.click(screen.getByRole('button', { name: /Start Talking/ }));
  expect(mockReplace).not.toHaveBeenCalled();
  mockAuth.mockReturnValue({ user: { uid: 'fixture-owner' }, loading: false, error: null, signInAnonymously: mockSignIn });
  view.rerender(<How />);
  expect(mockReplace).toHaveBeenCalledWith('/onboarding');
});
it.each(['Enter', ' '])('allows keyboard activation of the visible Welcome control: %s', key => {
  const next = jest.fn();
  render(<Welcome onNext={next} />);
  const button = screen.getByRole('button', { name: 'Continue' });
  expect(button).toHaveAttribute('tabindex', '0');
  fireEvent.keyDown(button, { key });
  expect(next).toHaveBeenCalledTimes(1);
});

it('does not redirect an already signed-in visitor reading How It Works', () => {
  mockAuth.mockReturnValue({ user: { uid: 'fixture-owner' }, loading: false, error: null, signInAnonymously: mockSignIn });
  render(<How />);
  expect(mockReplace).not.toHaveBeenCalled();
});
