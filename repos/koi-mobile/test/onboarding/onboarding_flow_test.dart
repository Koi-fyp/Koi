import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/onboarding/onboarding_screen.dart';
import 'package:koi_mobile/onboarding/progress_indicator.dart';
import 'package:koi_mobile/onboarding/steps/avatar_step.dart';
import 'package:koi_mobile/onboarding/steps/language_step.dart';
import 'package:koi_mobile/onboarding/steps/privacy_step.dart';

import '../support/fake_auth.dart';
import '../support/real_fonts.dart';

void main() {
  useRealFonts();

  testWidgets('full flow mirrors page.tsx: skips Avatar (Q8), saves web ids, '
      "defaults avatar to 'male_human' (Q7)", (tester) async {
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
    await tester.tap(find.byKey(const Key('companion-raza')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final cta = find.byKey(const Key('companion-continue'));
    await tester.ensureVisible(cta);
    await tester.pump();
    await tester.tap(cta);
    await tester.pump();

    // 3 AI disclosure
    await tester.ensureVisible(find.byKey(const Key('check-ai')));
    await tester.tap(find.byKey(const Key('check-ai')));
    await tester.tap(find.byKey(const Key('check-privacy')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('disclosure-next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Q8: straight to Language (5); Avatar (4) is skipped.
    expect(find.byType(AvatarStep), findsNothing);
    expect(find.byType(LanguageStep), findsOneWidget);
    double w(int i) =>
        tester.getSize(find.byKey(Key('progress-segment-$i'))).width;
    expect(w(4), greaterThan(w(3) * 1.9)); // currentStep = 5 - 1 = 4

    await tester.tap(find.byKey(const Key('language-ur')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('language-next')));
    await tester.pump();

    // 6 Notification
    await tester.tap(find.byKey(const Key('notif-time')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('notification-complete')));
    await tester.pump();

    expect(onboarding.isComplete, isTrue);
    expect(users.saved, hasLength(1));
    final (uid, data) = users.saved.single;
    expect(uid, 'u1');
    expect(data.avatar, 'male_human');
    expect(data.companion, 'raza');
    expect(data.language, 'ur');
    expect(data.notificationTime, '09:30');
    expect(data.notificationsEnabled, isTrue);
  });

  test('Q8 constant: disclosure jumps to step 5 like web setStep(5)', () {
    expect(OnboardingScreen.stepAfterDisclosure, 5);
    expect(OnboardingScreen.totalSteps, 7);
  });
}
