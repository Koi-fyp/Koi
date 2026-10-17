import React from 'react';
import { render, screen, cleanup } from '@testing-library/react';
jest.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: null, loading: false, signInAnonymously: jest.fn() }) }));
jest.mock('@/lib/firebase', () => ({ FirebaseConfigurationError: class extends Error {} }));
jest.mock('@/lib/onboarding', () => ({ isOnboardingComplete: () => false }));
import Landing from '@/app/page';
import About from '@/app/about/page';
import How from '@/app/how-it-works/page';
import Privacy from '@/app/(authenticated)/settings/privacy/page';
import Export from '@/app/(authenticated)/settings/export/page';
beforeAll(() => { global.IntersectionObserver = class { observe() {} unobserve() {} disconnect() {} } as unknown as typeof IntersectionObserver; });
afterEach(cleanup);
it.each([Landing, About, How])('public copy does not advertise fabricated usage, guaranteed availability or no storage', Component => {
  const { container } = render(<Component />);
  expect(container.textContent).not.toMatch(/2,400\+|50,000\+|50 users in Lahore|no waiting, ever|zero data storage|Thousands of conversations|Always free|We cannot read your conversations/);
});
it('privacy shows no manufactured successful activity or deletion promise', () => {
  const { container } = render(<Privacy />);
  expect(screen.getByText('No recorded activity available')).toBeInTheDocument();
  expect(container.textContent).not.toMatch(/2 minutes ago|1 hour ago|Yesterday|Not even we can read|Military-grade|permanently remove all/);
  expect(screen.getByRole('button', { name: /Delete My Account/ })).toBeDisabled();
  expect(container.textContent).toContain('readable prompts');
});
it('does not permit a synthetic wellness PDF', () => {
  render(<Export />);
  expect(screen.getByRole('button', { name: /Generate Wellness Report/ })).toBeDisabled();
  expect(screen.queryByText(/mood has improved|487|2025-04-15/)).not.toBeInTheDocument();
});
