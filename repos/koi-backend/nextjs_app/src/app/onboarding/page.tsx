'use client';
import { useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import ProgressIndicator from '@/components/onboarding/ProgressIndicator';
import WelcomeStep from '@/components/onboarding/WelcomeStep';
import PrivacyStep from '@/components/onboarding/PrivacyStep';
import CompanionSelectionStep from '@/components/onboarding/CompanionSelectionStep';
import AIDisclosureStep from '@/components/onboarding/AIDisclosureStep';
import AvatarStep from '@/components/onboarding/AvatarStep';
import LanguageStep from '@/components/onboarding/LanguageStep';
import NotificationStep from '@/components/onboarding/NotificationStep';
import { completeOnboarding } from '@/lib/onboarding';

type AvatarId = 'female_human' | 'male_human' | 'fox';
type Language = 'en' | 'ur';

// Steps: 0=Welcome, 1=Privacy, 2=CompanionSelection, 3=AIDisclosure, 4=Avatar, 5=Language, 6=Notification
const TOTAL_STEPS = 7;

interface OnboardingPageProps {
  readonly initialStep?: number;
}

export default function OnboardingPage(props: Readonly<OnboardingPageProps>) {
  const { initialStep = 0 } = props;
  const [step, setStep] = useState(initialStep);
  const [avatar, setAvatar] = useState<AvatarId | null>(null);
  const [language, setLanguage] = useState<Language>('en');
  const [companion, setCompanion] = useState<string>('koi');
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

  const handleCompanionNext = useCallback((companionId: string) => {
    setCompanion(companionId);
    setStep((s) => s + 1);
  }, []);

  const handleComplete = useCallback(async (notifTime: string, notifEnabled: boolean) => {
    const selectedAvatar = avatar || 'fox';

    await completeOnboarding({
      avatar: selectedAvatar,
      companion: companion as 'aisha' | 'raza' | 'koi',
      language,
      notificationTime: notifTime,
      notificationsEnabled: notifEnabled,
    });
    router.replace('/chat');
  }, [avatar, companion, language, router]);

  const showProgress = step > 0;
  const showCompanionSelection = step === 2;
  const showDisclosure = step === 3;
  const showAvatar = step === 4;
  const showLanguage = step === 5;
  const showNotification = step === 6;

  return (
    <div className="flex flex-col min-h-screen">
      {showProgress && (
        <ProgressIndicator currentStep={step - 1} totalSteps={TOTAL_STEPS - 1} />
      )}

      {step === 0 && <WelcomeStep onNext={advance} />}
      {step === 1 && <PrivacyStep onNext={advance} />}
      {showCompanionSelection && <CompanionSelectionStep onNext={handleCompanionNext} />}
      {showDisclosure && <AIDisclosureStep onNext={() => setStep(5)} />}
      {showAvatar && <AvatarStep onNext={handleAvatarNext} />}
      {showLanguage && <LanguageStep onNext={handleLanguageNext} />}
      {showNotification && <NotificationStep onComplete={handleComplete} />}
    </div>
  );
}
