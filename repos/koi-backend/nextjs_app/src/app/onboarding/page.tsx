'use client';
import { useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import ProgressIndicator from '@/components/onboarding/ProgressIndicator';
import WelcomeStep from '@/components/onboarding/WelcomeStep';
import PrivacyStep from '@/components/onboarding/PrivacyStep';
import AIDisclosureStep from '@/components/onboarding/AIDisclosureStep';
import AvatarStep from '@/components/onboarding/AvatarStep';
import LanguageStep from '@/components/onboarding/LanguageStep';
import NotificationStep from '@/components/onboarding/NotificationStep';
import { completeOnboarding } from '@/lib/onboarding';

type AvatarId = 'female_human' | 'male_human' | 'fox';
type Language = 'en' | 'ur';

// Steps: 0=Welcome, 1=Privacy, 2=AIDisclosure, 3=Avatar, 4=Language, 5=Notification
const TOTAL_STEPS = 6;

interface OnboardingPageProps {
  initialStep?: number;
}

export default function OnboardingPage({ initialStep = 0 }: OnboardingPageProps) {
  const [step, setStep] = useState(initialStep);
  const [avatar, setAvatar] = useState<AvatarId | null>(null);
  const [language, setLanguage] = useState<Language>('en');
  const router = useRouter();

  const advance = useCallback(() => setStep((s) => s + 1), []);

  const handleAvatarNext = useCallback((selected: AvatarId) => {
    setAvatar(selected);
    setStep((s) => s + 1);
  }, []);

  const handleLanguageNext = useCallback((lang: Language) => {
    setLanguage(lang);
    setStep((s) => s + 1);
  }, []);

  const handleComplete = useCallback(async (notifTime: string, notifEnabled: boolean) => {
    await completeOnboarding({
      avatar: avatar!,
      language,
      notificationTime: notifTime,
      notificationsEnabled: notifEnabled,
    });
    router.replace('/chat');
  }, [avatar, language, router]);

  return (
    <div className="flex flex-col min-h-screen bg-[#F5F5F5]">
      {step > 0 && (
        <ProgressIndicator currentStep={step - 1} totalSteps={TOTAL_STEPS - 1} />
      )}

      {step === 0 && <WelcomeStep onNext={advance} />}
      {step === 1 && <PrivacyStep onNext={advance} />}
      {step === 2 && <AIDisclosureStep onNext={advance} />}
      {step === 3 && <AvatarStep onNext={handleAvatarNext} />}
      {step === 4 && <LanguageStep onNext={handleLanguageNext} />}
      {step === 5 && <NotificationStep onComplete={handleComplete} />}
    </div>
  );
}
