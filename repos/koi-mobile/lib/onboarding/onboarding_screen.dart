import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../avatar/avatar_state.dart';
import '../safety_plan/safety_plan_onboarding_step.dart';
import '../theme/koi_colors.dart';
import 'onboarding_service.dart';
import 'progress_indicator.dart';
import 'steps/ai_disclosure_step.dart';
import 'steps/companion_step.dart';
import 'steps/language_step.dart';
import 'steps/notification_step.dart';
import 'steps/privacy_step.dart';
import 'steps/welcome_step.dart';

/// Mirrors repos/koi-backend/nextjs_app/src/app/onboarding/page.tsx
/// (feat/avatar-webview-host 223e97c).
///
/// One companion choice selects the matching avatar: Aisha/female,
/// Raza/male, Koi/fox (page.tsx:20). Steps: 0=Welcome, 1=Privacy,
/// 2=CompanionSelection, 3=AIDisclosure, 4=Language, 5=Notification
/// (page.tsx:21).
///
/// Mobile-only: after Companion, an optional safety plan sub-screen
/// ([SafetyPlanOnboardingStep]) shows before AI Disclosure. It is not a
/// counted step: [totalSteps], the step numbers and the progress dots stay
/// as on Web (decision 2026-10-20, option B).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({
    super.key,
    this.initialStep = 0,
    this.openUrl,
    this.pickTime,
  });

  /// page.tsx `initialStep` prop.
  final int initialStep;

  /// Test hooks for the tel: links and the time picker.
  final UrlOpener? openUrl;
  final TimePicker? pickTime;

  static const int totalSteps = 6; // TOTAL_STEPS (page.tsx:22)

  /// The step Android back returns to from [step] (decision 2026-10-14):
  /// the previous one. Null on Welcome.
  static int? previousStep(int step) => step <= 0 ? null : step - 1;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late int _step = widget.initialStep;
  String _language = 'en';

  /// page.tsx:40 default 'raza'.
  CompanionAvatar _companion = CompanionAvatar.raza;

  /// The safety plan sub-screen is showing (still step 2 for progress).
  bool _safetyPlan = false;

  void _advance() => setState(() => _step++);

  /// Android back. Web keeps the step in component state, so browser back
  /// leaves /onboarding and the landing page sends a signed-in user straight
  /// back. Mobile instead steps back; on Welcome it signs out (dropping the
  /// anonymous session created by "Start Talking") so the root router shows
  /// the landing page (decision 2026-10-14, option a).
  void _onBack(bool didPop, Object? _) {
    if (didPop) return;
    if (_safetyPlan) {
      setState(() => _safetyPlan = false);
      return;
    }
    final prev = OnboardingScreen.previousStep(_step);
    if (prev != null) {
      setState(() => _step = prev);
    } else {
      ref.read(authServiceProvider).signOut();
    }
  }

  Future<void> _handleComplete(String notifTime, bool notifEnabled) async {
    // page.tsx:68: aisha → female_human, raza → male_human, koi → fox.
    await ref
        .read(onboardingServiceProvider)
        .complete(
          OnboardingData(
            avatar: _companion.avatarId,
            companion: _companion.companion,
            language: _language,
            notificationTime: notifTime,
            notificationsEnabled: notifEnabled,
          ),
        );
    // router.replace('/chat'): RootRouter switches to the shell as soon as
    // the complete flag is set.
  }

  @override
  Widget build(BuildContext context) {
    final step = switch (_step) {
      0 => WelcomeStep(onNext: _advance),
      1 => PrivacyStep(onNext: _advance),
      2 when _safetyPlan => SafetyPlanOnboardingStep(
        onNext: () => setState(() {
          _safetyPlan = false;
          _step++;
        }),
      ),
      2 => CompanionSelectionStep(
        initialSelection: _companion.companion,
        onNext: (id) => setState(() {
          _companion = CompanionAvatar.fromCompanion(id) ?? _companion;
          _safetyPlan = true;
        }),
      ),
      3 => AIDisclosureStep(
        onNext: _advance, // page.tsx:97 setStep(4)
        openUrl: widget.openUrl ?? AIDisclosureStep.defaultOpen,
      ),
      4 => LanguageStep(
        onNext: (lang) => setState(() {
          _language = lang;
          _step++;
        }),
      ),
      5 => NotificationStep(
        onComplete: _handleComplete,
        pickTime: widget.pickTime ?? NotificationStep.defaultPicker,
      ),
      _ => const SizedBox.shrink(),
    };

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: _onBack,
      child: _scaffold(step),
    );
  }

  Widget _scaffold(Widget step) {
    return Scaffold(
      backgroundColor: KoiColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_step > 0) // showProgress
              OnboardingProgressIndicator(
                currentStep: _step - 1,
                totalSteps: OnboardingScreen.totalSteps - 1,
              ),
            Expanded(
              child: KeyedSubtree(
                key: ValueKey(
                  _safetyPlan
                      ? 'onboarding-safety-plan'
                      : 'onboarding-step-$_step',
                ),
                child: step,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
