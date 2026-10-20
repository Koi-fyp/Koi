import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/onboarding/onboarding_screen.dart';
import 'package:koi_mobile/onboarding/progress_indicator.dart';
import 'package:koi_mobile/onboarding/steps/language_step.dart';
import 'package:koi_mobile/onboarding/steps/notification_step.dart';
import 'package:koi_mobile/onboarding/steps/privacy_step.dart';

import '../support/fake_auth.dart';
import '../support/real_fonts.dart';

void main() {
  useRealFonts();

  // web 223e97c app/onboarding/page.tsx:68
  const avatars = {'aisha': 'female_human', 'raza': 'male_human', 'koi': 'fox'};

  for (final MapEntry(key: companion, value: avatar) in avatars.entries) {
    testWidgets('ATC-M1-19 full flow mirrors page.tsx (6 steps): $companion saves '
        "avatar '$avatar'", (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(1080, 2400);
      addTearDown(tester.view.reset);

      final onboarding = onboardingStore();
      final users = RecordingUserWriter();
      await tester.pumpWidget(
        ProviderScope(
          overrides: overridesFor(
            FakeAuthService(
              fakeUser: const KoiUser(uid: 'u1', isAnonymous: true),
            ),
            onboarding,
            users: users,
          ),
          child: MaterialApp(
            home: OnboardingScreen(
              openUrl: (_) async {},
              pickTime: (_, _) async => const TimeOfDay(hour: 9, minute: 30),
            ),
          ),
        ),
      );

      // 0 Welcome: no progress bar; auto-advance after 2200ms.
      expect(find.byType(OnboardingProgressIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 2300));
      await tester.pump();

      // 1 Privacy
      expect(find.byType(PrivacyStep), findsOneWidget);
      expect(find.byType(OnboardingProgressIndicator), findsOneWidget);
      await tester.tap(find.byKey(const Key('privacy-next')));
      await tester.pump();

      // 2 Companion
      final card = find.byKey(Key('companion-$companion'));
      await tester.ensureVisible(card);
      await tester.pump();
      await tester.tap(card);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final cta = find.byKey(const Key('companion-continue'));
      await tester.ensureVisible(cta);
      await tester.pump();
      await tester.tap(cta);
      await tester.pump();

      // Optional safety plan sub-screen (not a counted step): Not now.
      await tester.tap(find.byKey(const Key('sp-onboarding-skip')));
      await tester.pump();

      // 3 AI disclosure → 4 Language (page.tsx:97 setStep(4), no skip).
      await tester.ensureVisible(find.byKey(const Key('check-ai')));
      await tester.tap(find.byKey(const Key('check-ai')));
      await tester.tap(find.byKey(const Key('check-privacy')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('disclosure-next')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(LanguageStep), findsOneWidget);
      double w(int i) =>
          tester.getSize(find.byKey(Key('progress-segment-$i'))).width;
      expect(w(3), greaterThan(w(2) * 1.9)); // currentStep = 4 - 1 = 3
      expect(find.byKey(const Key('progress-segment-5')), findsNothing);

      await tester.tap(find.byKey(const Key('language-ur')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('language-next')));
      await tester.pump();

      // 5 Notification (last step)
      expect(find.byType(NotificationStep), findsOneWidget);
      await tester.tap(find.byKey(const Key('notif-time')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('notification-complete')));
      await tester.pump();

      expect(onboarding.isCompleteFor('u1'), isTrue);
      expect(users.saved, hasLength(1));
      final (uid, data) = users.saved.single;
      expect(uid, 'u1');
      expect(data.avatar, avatar);
      expect(data.companion, companion);
      expect(data.language, 'ur');
      expect(data.notificationTime, '09:30');
      expect(data.notificationsEnabled, isTrue);
    });
  }

  test('ATC-M1-20 6 steps like web TOTAL_STEPS; back goes to the previous step', () {
    expect(OnboardingScreen.totalSteps, 6);
    expect(OnboardingScreen.previousStep(4), 3); // Language → AI Disclosure
  });
}
