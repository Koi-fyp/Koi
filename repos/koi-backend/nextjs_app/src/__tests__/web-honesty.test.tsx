import React from 'react';
import { render, screen, cleanup } from '@testing-library/react';
jest.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: null, loading: false, signInAnonymously: jest.fn() }) }));
jest.mock('@/contexts/ConversationContext', () => ({ useSharedConversation: () => ({ uid: null, session: null }) }));
jest.mock('@/lib/firebase', () => ({ FirebaseConfigurationError: class extends Error {} }));
jest.mock('@/lib/onboarding', () => ({ isOnboardingComplete: () => false, resolveOnboardingComplete: async () => false }));
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
  expect(screen.getByRole('link', { name: 'Open Wellness Report' })).toHaveAttribute('href', '/settings/report');
  expect(screen.queryByRole('button', { name: /Generate Wellness Report/ })).not.toBeInTheDocument();
  expect(screen.queryByText(/mood has improved|487|2025-04-15/)).not.toBeInTheDocument();
  expect(screen.getByRole('heading', {name:'Export My Data'})).toBeInTheDocument();
  expect(screen.getByText(/not a clinical assessment/)).toBeInTheDocument();
  expect(document.body.textContent).not.toMatch(/Report generated locally|No personal information shared|Download & keep forever/);
});

import PrivacyStep from '@/components/onboarding/PrivacyStep';
import AIDisclosureStep from '@/components/onboarding/AIDisclosureStep';
it('onboarding discloses plaintext inference without nonexistent policy agreement', () => {
  const view = render(<><PrivacyStep onNext={() => {}} /><AIDisclosureStep onNext={() => {}} /></>);
  expect(view.container.textContent).not.toMatch(/What we never store|Conversations shared with third parties|agree to Privacy Policy/);
  expect(view.getByText('Inference receives readable messages and recent context')).toBeInTheDocument();
});
