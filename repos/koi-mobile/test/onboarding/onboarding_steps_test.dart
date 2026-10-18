import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/onboarding/progress_indicator.dart';
import 'package:koi_mobile/onboarding/steps/ai_disclosure_step.dart';
import 'package:koi_mobile/onboarding/steps/companion_step.dart';
import 'package:koi_mobile/onboarding/steps/language_step.dart';
import 'package:koi_mobile/onboarding/steps/notification_step.dart';
import 'package:koi_mobile/onboarding/steps/privacy_step.dart';
import 'package:koi_mobile/onboarding/steps/welcome_step.dart';
import 'package:koi_mobile/theme/koi_colors.dart';
import 'package:koi_mobile/widgets/neo_button.dart';

import '../support/real_fonts.dart';

/// One test group per onboarding step, each on a 360x800dp phone with the
/// real bundled fonts (so overflow checks are meaningful).
void main() {
  useRealFonts();

  Future<void> pump(WidgetTester tester, Widget step) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(backgroundColor: KoiColors.background, body: step),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull, reason: 'no overflow at 360dp');
  }

  bool enabled(WidgetTester tester, Key key) =>
      tester.widget<NeoButton>(find.byKey(key)).onPressed != null;

  group('ATC-M1-12 WelcomeStep', () {
    testWidgets('copy, and auto-advances after 2200ms', (tester) async {
      var next = 0;
      await pump(tester, WelcomeStep(onNext: () => next++));
      expect(find.text('KOI'), findsOneWidget);
      expect(find.text(WelcomeStep.tagline), findsOneWidget);
      expect(find.text('TAP TO CONTINUE'), findsOneWidget);
      expect(next, 0); // 1s pumped so far
      await tester.pump(const Duration(milliseconds: 1200));
      expect(next, 1);
    });

    testWidgets('tap advances immediately', (tester) async {
      var next = 0;
      await pump(tester, WelcomeStep(onNext: () => next++));
      await tester.tap(find.byKey(const Key('welcome-step')));
      expect(next, 1);
    });
  });

  group('ATC-M1-13 PrivacyStep', () {
    testWidgets('both lists and "I Understand →"', (tester) async {
      var next = 0;
      await pump(tester, PrivacyStep(onNext: () => next++));
      expect(find.text('Privacy Matters'), findsOneWidget);
      expect(find.text('What we store'), findsOneWidget);
      expect(find.text('Before you share'), findsOneWidget);
      for (final s in [...PrivacyStep.stored, ...PrivacyStep.beforeYouShare]) {
        expect(find.text(s), findsOneWidget);
      }
      // Changed in Prompt 28: mobile stores daily check-ins (encrypted),
      // so web's PrivacyStep.tsx:11 line is replaced; old claims gone.
      expect(
        find.text('Your daily check-ins, stored encrypted on this device'),
        findsOneWidget,
      );
      expect(
        find.text('Local reminder preferences (not completed mood check-ins)'),
        findsNothing,
      );
      expect(find.text('Check-in mood responses'), findsNothing);
      expect(find.text('What we never store'), findsNothing);
      expect(find.text('Any data sold to advertisers'), findsNothing);
      await tester.tap(find.byKey(const Key('privacy-next')));
      expect(next, 1);
    });
  });

  group('ATC-M1-14 CompanionSelectionStep', () {
    testWidgets("defaults to 'raza'; selecting changes the CTA and the id", (
      tester,
    ) async {
      String? chosen;
      await pump(tester, CompanionSelectionStep(onNext: (id) => chosen = id));
      expect(find.text('Choose Your Companion'), findsOneWidget);
      expect(find.text('Continue with Raza'), findsOneWidget);

      await tester.tap(find.byKey(const Key('companion-aisha')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Continue with Aisha'), findsOneWidget);

      final cta = find.byKey(const Key('companion-continue'));
      await tester.ensureVisible(cta);
      await tester.pump();
      await tester.tap(cta);
      expect(chosen, 'aisha');
    });

    testWidgets('web 223e97c cards: Female/Male previews, fox unavailable, '
        'new traits and subtitle', (tester) async {
      await pump(tester, CompanionSelectionStep(onNext: (_) {}));
      expect(
        find.text(
          'Choose your companion and matching avatar. Aisha uses the female '
          'model, Raza the male model, and Koi keeps the fox choice.',
        ),
        findsOneWidget,
      );
      String asset(String id) =>
          ((tester.widget<Image>(find.byKey(Key('companion-preview-$id'))))
                      .image
                  as AssetImage)
              .assetName;
      expect(asset('aisha'), 'assets/images/Female.png');
      expect(asset('raza'), 'assets/images/Male.png');
      expect(find.bySemanticsLabel('Aisha avatar preview'), findsOneWidget);
      expect(find.bySemanticsLabel('Raza avatar preview'), findsOneWidget);

      final fox = find.byKey(const Key('companion-preview-fox'));
      await tester.ensureVisible(fox);
      await tester.pump();
      expect(
        find.descendant(
          of: fox,
          matching: find.text('Fox preview unavailable'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Fox avatar preview unavailable')),
        findsOneWidget,
      );
      for (final trait in [
        'Warm & caring · Female avatar',
        'Calm & grounded · Male avatar',
        'Playful & curious · Fox choice',
      ]) {
        expect(find.text(trait), findsOneWidget);
      }
      // No emoji avatars any more (only the fox placeholder's 🦊).
      expect(find.text('👩'), findsNothing);
      expect(find.text('👨'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('initialSelection seeds the choice', (tester) async {
      await pump(
        tester,
        CompanionSelectionStep(initialSelection: 'koi', onNext: (_) {}),
      );
      expect(find.text('Continue with Koi'), findsOneWidget);
    });
  });

  group('ATC-M1-15 AIDisclosureStep', () {
    testWidgets('"I Agree" needs both boxes; helplines open tel: links', (
      tester,
    ) async {
      var next = 0;
      final opened = <Uri>[];
      await pump(
        tester,
        AIDisclosureStep(
          onNext: () => next++,
          openUrl: (u) async => opened.add(u),
        ),
      );
      expect(find.text('Important Notice'), findsOneWidget);
      expect(find.text('Crisis Helplines (Pakistan)'), findsOneWidget);
      // web 223e97c AIDisclosureStep.tsx:30; no Privacy Policy / Terms.
      expect(
        AIDisclosureStep.privacyCheck,
        'I understand saved history is encrypted, while inference receives '
        'readable text',
      );
      expect(find.textContaining('Terms of Service'), findsNothing);
      for (final h in AIDisclosureStep.helplines) {
        expect(find.text(h.name), findsOneWidget);
        expect(find.text(h.tel), findsOneWidget);
      }

      const agree = Key('disclosure-next');
      expect(enabled(tester, agree), isFalse);
      await tester.ensureVisible(find.byKey(const Key('check-ai')));
      await tester.tap(find.byKey(const Key('check-ai')));
      await tester.pump();
      expect(enabled(tester, agree), isFalse);
      // The label text toggles too, like a <label>.
      await tester.ensureVisible(find.text(AIDisclosureStep.privacyCheck));
      await tester.tap(find.text(AIDisclosureStep.privacyCheck));
      await tester.pump();
      expect(enabled(tester, agree), isTrue);
      await tester.tap(find.byKey(agree));
      expect(next, 1);

      await tester.ensureVisible(find.byKey(const Key('tel-tel:03117786264')));
      await tester.tap(find.byKey(const Key('tel-tel:03117786264')));
      expect(opened, [Uri.parse('tel:03117786264')]);
    });
  });

  group('ATC-M1-16 LanguageStep', () {
    testWidgets("defaults to 'en'; can pick 'ur'", (tester) async {
      final chosen = <String>[];
      await pump(tester, LanguageStep(onNext: chosen.add));
      expect(find.text('Select Language'), findsOneWidget);
      expect(find.text('اردو'), findsOneWidget);
      await tester.tap(find.byKey(const Key('language-next')));
      await tester.tap(find.byKey(const Key('language-ur')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('language-next')));
      expect(chosen, ['en', 'ur']);
    });
  });

  group('ATC-M1-17 NotificationStep', () {
    testWidgets("defaults '20:00' + enabled; picker and switch update values", (
      tester,
    ) async {
      final results = <(String, bool)>[];
      await pump(
        tester,
        NotificationStep(
          onComplete: (t, e) => results.add((t, e)),
          pickTime: (_, initial) async {
            expect(initial, const TimeOfDay(hour: 20, minute: 0));
            return const TimeOfDay(hour: 7, minute: 5);
          },
        ),
      );
      expect(find.text('Daily Check-ins'), findsOneWidget);
      // web 223e97c NotificationStep.tsx:44, :52, :55 ("Web notifications"
      // → "Notifications" on mobile).
      expect(
        find.text(
          'Save a preferred check-in time on this device. Notifications and '
          'scheduled messages are not enabled.',
        ),
        findsOneWidget,
      );
      expect(find.text('Save daily check-in preference'), findsOneWidget);
      expect(
        find.text('Preference only; no notification is scheduled'),
        findsOneWidget,
      );
      expect(find.text('Enable daily reminders'), findsNothing);
      expect(find.text('20:00'), findsOneWidget);
      expect(find.text('Available 6:00 AM – 11:00 PM'), findsOneWidget);

      await tester.tap(find.byKey(const Key('notif-time')));
      await tester.pump();
      expect(find.text('07:05'), findsOneWidget);

      await tester.tap(find.byKey(const Key('notification-complete')));
      await tester.tap(find.byKey(const Key('notif-switch')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Reminder time'), findsNothing); // {enabled && ...}
      await tester.tap(find.byKey(const Key('notification-complete')));
      expect(results, [('07:05', true), ('07:05', false)]);
    });
  });

  group('ATC-M1-18 OnboardingProgressIndicator', () {
    testWidgets('done segments faded, active one double width', (tester) async {
      await pump(
        tester,
        const OnboardingProgressIndicator(currentStep: 2, totalSteps: 6),
      );
      double w(int i) =>
          tester.getSize(find.byKey(Key('progress-segment-$i'))).width;
      expect(w(2), closeTo(2 * w(3), 0.01));
      expect(w(0), closeTo(w(5), 0.01));
      double opacity(int i) => tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: find.byKey(Key('progress-segment-$i')),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity;
      expect(
        [for (var i = 0; i < 6; i++) opacity(i)],
        [0.55, 0.55, 1, 1, 1, 1],
      );
    });
  });
}
