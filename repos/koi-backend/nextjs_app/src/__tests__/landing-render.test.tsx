import React from 'react';
import { render, screen } from '@testing-library/react';
const mockReplace = jest.fn();
jest.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: null, loading: false, error: null, signInAnonymously: jest.fn() }) }));
jest.mock('next/navigation', () => ({ useRouter: () => ({ replace: mockReplace }) }));
jest.mock('@/lib/firebase', () => ({ FirebaseConfigurationError: class extends Error {} }));
jest.mock('@/lib/onboarding', () => ({ isOnboardingComplete: () => false, resolveOnboardingComplete: async () => false }));
import Landing from '@/app/page';
const nextConfig = require('../../next.config.js');
const { PHASE_DEVELOPMENT_SERVER, PHASE_PRODUCTION_BUILD } = require('next/constants');

beforeAll(() => { global.IntersectionObserver = class { observe() {} unobserve() {} disconnect() {} } as unknown as typeof IntersectionObserver; });

it('renders the landing hero and the sign-in CTA for a signed-out visitor', () => {
  render(<Landing />);
  expect(screen.getByRole('heading', { level: 1, name: /Your\s+mind\s+deserves a\s+friend\./ })).toBeInTheDocument();
  const cta = screen.getByRole('button', { name: /Start Talking/ });
  expect(cta).toBeEnabled();
  expect(screen.getByRole('button', { name: /Get Started/ })).toBeEnabled();
  expect(mockReplace).not.toHaveBeenCalled();
});

it('keeps dev-server output apart from production build output', () => {
  // A build that empties the dev server's distDir leaves / unstyled and unhydrated.
  expect(nextConfig(PHASE_DEVELOPMENT_SERVER).distDir).toBe('.next-dev');
  expect(nextConfig(PHASE_PRODUCTION_BUILD).distDir).toBeUndefined();
});
