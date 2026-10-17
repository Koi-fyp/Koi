'use client';
import { useState, useCallback, useEffect, useRef } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { useAuth } from '@/contexts/AuthContext';
import { useAvatarPreference } from '@/hooks/useAvatarPreference';
import ProgressIndicator from '@/components/onboarding/ProgressIndicator';
import WelcomeStep from '@/components/onboarding/WelcomeStep';
import PrivacyStep from '@/components/onboarding/PrivacyStep';
import CompanionSelectionStep from '@/components/onboarding/CompanionSelectionStep';
import AIDisclosureStep from '@/components/onboarding/AIDisclosureStep';
import LanguageStep from '@/components/onboarding/LanguageStep';
import NotificationStep from '@/components/onboarding/NotificationStep';
import { completeOnboarding } from '@/lib/onboarding';
import type { CompanionId } from '@/lib/avatar/avatarPreference';
import { validTime } from '@/lib/preferences/userPreferences';

type Language = 'en' | 'ur';

// One companion choice selects the matching avatar: Aisha/female, Raza/male, Koi/fox.
// Steps: 0=Welcome, 1=Privacy, 2=CompanionSelection, 3=AIDisclosure, 4=Language, 5=Notification
const TOTAL_STEPS = 6;

interface OnboardingPageProps {
  readonly initialStep?: number;
}

export default function OnboardingPage(props: Readonly<OnboardingPageProps>) {
  const { initialStep = 0 } = props;
  const { user, loading: authLoading } = useAuth();
  const active = useRef(true);
  const currentUid = useRef(user?.uid); currentUid.current = user?.uid;
  useEffect(() => { active.current = true; return () => { active.current = false; }; }, []);
  const savedPreference = useAvatarPreference(user?.uid, authLoading);
  const [step, setStep] = useState(initialStep);
  const [languageChoice, setLanguage] = useState<{ uid: string; language: Language } | null>(null);
  const profile = savedPreference.status === 'ready' ? savedPreference.profile : null;
  const language = languageChoice && languageChoice.uid === user?.uid ? languageChoice.language : profile?.language === 'ur' ? 'ur' : 'en';
  const [choice, setChoice] = useState<{ uid: string; companion: CompanionId } | null>(null);
  const saved = savedPreference.status === 'ready' && savedPreference.preference.status === 'selected' ? savedPreference.preference.companion : 'raza';
  const companion = choice && choice.uid === user?.uid ? choice.companion : saved;
  const [saveError, setSaveError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [locallySavedUid, setLocallySavedUid] = useState<string | null>(null);
  useEffect(() => { setSaving(false); setSaveError(null); setLocallySavedUid(null); }, [user?.uid]);
  const router = useRouter();

  const advance = useCallback(() => setStep((s) => s + 1), []);

  const handleLanguageNext = useCallback((lang: Language) => {
    if (!user) return;
    setLanguage({ uid: user.uid, language: lang });
    setStep((s) => s + 1);
  }, [user]);

  const handleCompanionNext = useCallback((companionId: CompanionId) => {
    if (!user) return;
    setChoice({ uid: user.uid, companion: companionId });
    setStep((s) => s + 1);
  }, [user]);

  const handleComplete = useCallback(async (notifTime: string, notifEnabled: boolean) => {
    if (saving || !user || savedPreference.status !== 'ready') return;
    const owner = user.uid;
    setSaving(true);
    setSaveError(null);
    try {
      const selectedAvatar = companion === 'aisha' ? 'female_human' : companion === 'raza' ? 'male_human' : 'fox';
      await completeOnboarding({ avatar: selectedAvatar, companion, language, notificationTime: notifTime, notificationsEnabled: notifEnabled }, () => {
        if (active.current && currentUid.current === owner) setLocallySavedUid(owner);
      });
      if (active.current && currentUid.current === owner) router.replace('/chat');
    } catch (error) {
      if (active.current && currentUid.current === owner) setSaveError(error instanceof Error ? error.message : 'Your selection could not be saved. Please try again.');
    } finally {
      if (active.current && currentUid.current === owner) setSaving(false);
    }
  }, [companion, language, router, saving, user, savedPreference.status]);

  const showProgress = step > 0;
  const showCompanionSelection = step === 2;
  const showDisclosure = step === 3;
  const showLanguage = step === 4;
  const showNotification = step === 5;

  return (
    <div className="flex flex-col min-h-screen">
      {showProgress && (
        <ProgressIndicator currentStep={step - 1} totalSteps={TOTAL_STEPS - 1} />
      )}

      {step === 0 && <WelcomeStep onNext={advance} />}
      {step === 1 && <PrivacyStep onNext={advance} />}
      {showCompanionSelection && (savedPreference.status === 'loading' ? <p role="status">Loading your saved companion...</p>
        : savedPreference.status === 'error' ? <p role="alert">Your saved companion could not be loaded. Reload to retry before choosing.</p>
        : <CompanionSelectionStep key={user?.uid} initialSelection={companion} onNext={handleCompanionNext} />)}
      {showDisclosure && <AIDisclosureStep onNext={() => setStep(4)} />}
      {showLanguage && <LanguageStep key={user?.uid} initialLanguage={language} onNext={handleLanguageNext} />}
      {showNotification && <>
        {saveError && <p role="alert" className="mx-auto mt-4 max-w-xl px-6 text-center text-red-700">{saveError}</p>}
        {locallySavedUid === user?.uid && <p role="status" className="mx-auto mt-4 max-w-xl px-6">Your companion is saved on this device. Account sync may still be pending. <Link href="/chat" className="underline">Continue with saved companion</Link></p>}
        <NotificationStep key={`${user?.uid}:${savedPreference.status}`} initialEnabled={profile?.notificationsEnabled ?? true} initialTime={validTime(profile?.notificationTime) ? profile.notificationTime : '20:00'} onComplete={handleComplete} saving={saving} disabled={savedPreference.status !== 'ready' || !user} />
      </>}
    </div>
  );
}
