/** @jest-environment jsdom */
import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import OnboardingPage from '@/app/onboarding/page';

describe('Onboarding Flow', () => {
  describe('AI Disclosure Screen', () => {
    it('should disable I Agree button until both checkboxes checked', () => {
      render(<OnboardingPage initialStep={2} />);

      const agreeButton = screen.getByText('I Agree');
      expect(agreeButton).toBeDisabled();

      fireEvent.click(screen.getByText('I understand KOI is an AI, not a therapist'));
      expect(agreeButton).toBeDisabled(); // still disabled after first checkbox

      fireEvent.click(screen.getByText('I agree to Privacy Policy and Terms of Service'));
      expect(agreeButton).not.toBeDisabled(); // enabled after both checked
    });

    it('should always show crisis helplines on disclosure screen', () => {
      render(<OnboardingPage initialStep={2} />);
      expect(screen.getByText('0311-7786264')).toBeInTheDocument();
      expect(screen.getByText('0800-22444')).toBeInTheDocument();
    });
  });

  describe('Avatar Selection', () => {
    it('should select avatar and highlight it', () => {
      render(<OnboardingPage initialStep={3} />);
      fireEvent.click(screen.getByTestId('avatar-fox'));
      expect(screen.getByTestId('avatar-fox')).toHaveClass('ring-2');
    });

    it('should not allow Continue without avatar selection', () => {
      render(<OnboardingPage initialStep={3} />);
      expect(screen.getByText('Continue')).toBeDisabled();
    });
  });

  describe('Onboarding Completion', () => {
    it('should store onboarding_complete in localStorage on finish', async () => {
      const { completeOnboarding } = await import('@/lib/onboarding');
      await completeOnboarding({
        avatar: 'fox',
        language: 'en',
        notificationTime: '20:00',
        notificationsEnabled: true,
      });
      expect(localStorage.getItem('koi_onboarding_complete')).toBe('true');
    });
  });
});
