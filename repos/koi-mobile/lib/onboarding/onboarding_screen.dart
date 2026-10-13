import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../theme/koi_colors.dart';
import 'onboarding_service.dart';
import 'progress_indicator.dart';
import 'steps/ai_disclosure_step.dart';
import 'steps/avatar_step.dart';
import 'steps/companion_step.dart';
import 'steps/language_step.dart';
import 'steps/notification_step.dart';
import 'steps/privacy_step.dart';
import 'steps/welcome_step.dart';

/// Mirrors repos/koi-backend/nextjs_app/src/app/onboarding/page.tsx.
///
/// Steps: 0=Welcome, 1=Privacy, 2=CompanionSelection, 3=AIDisclosure,
/// 4=Avatar, 5=Language, 6=Notification.
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

  static const int totalSteps = 7; // TOTAL_STEPS

  /// Q8 (2026-10-13): AIDisclosureStep advances with `setStep(5)` on web,
  /// skipping AvatarStep (4). Mobile mirrors this exactly, as decided. This
  /// is most likely a web bug; when web fixes it, change this to step + 1.
  static const int stepAfterDisclosure = 5;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late int _step = widget.initialStep;
  String? _avatar; // useState<AvatarId | null>(null)
  String _language = 'en';
  String _companion = 'koi';

  void _advance() => setState(() => _step++);

  Future<void> _handleComplete(String notifTime, bool notifEnabled) async {
    // Web: `avatar || 'fox'`. Mobile (Q7): `avatar ?? 'male_human'`.
    final selectedAvatar = _avatar ?? KoiAvatarId.fallback;
    await ref
        .read(onboardingServiceProvider)
        .complete(
          OnboardingData(
            avatar: selectedAvatar,
            companion: _companion,
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
      2 => CompanionSelectionStep(
        onNext: (id) => setState(() {
          _companion = id;
          _step++;
        }),
      ),
      3 => AIDisclosureStep(
        onNext: () =>
            setState(() => _step = OnboardingScreen.stepAfterDisclosure),
        openUrl: widget.openUrl ?? AIDisclosureStep.defaultOpen,
      ),
      4 => AvatarStep(
        onNext: (id) => setState(() {
          _avatar = id;
          _step++;
        }),
      ),
      5 => LanguageStep(
        onNext: (lang) => setState(() {
          _language = lang;
          _step++;
        }),
      ),
      6 => NotificationStep(
        onComplete: _handleComplete,
        pickTime: widget.pickTime ?? NotificationStep.defaultPicker,
      ),
      _ => const SizedBox.shrink(),
    };

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
                key: ValueKey('onboarding-step-$_step'),
                child: step,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
