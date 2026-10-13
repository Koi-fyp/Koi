import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/app/root_router.dart';
import 'package:koi_mobile/chat/chat_screen.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/info/about_screen.dart';
import 'package:koi_mobile/info/how_it_works_screen.dart';
import 'package:koi_mobile/landing/landing_screen.dart';
import 'package:koi_mobile/onboarding/onboarding_screen.dart';
import 'package:koi_mobile/onboarding/steps/ai_disclosure_step.dart';
import 'package:koi_mobile/onboarding/steps/avatar_step.dart';
import 'package:koi_mobile/onboarding/steps/companion_step.dart';
import 'package:koi_mobile/onboarding/steps/language_step.dart';
import 'package:koi_mobile/onboarding/steps/notification_step.dart';
import 'package:koi_mobile/onboarding/steps/privacy_step.dart';
import 'package:koi_mobile/onboarding/steps/welcome_step.dart';
import 'package:koi_mobile/progress/progress_screen.dart';
import 'package:koi_mobile/settings/export_screen.dart';
import 'package:koi_mobile/settings/import_screen.dart';
import 'package:koi_mobile/settings/privacy_screen.dart';
import 'package:koi_mobile/settings/settings_screen.dart';
import 'package:koi_mobile/settings/widgets/avatar_picker.dart';
import 'package:koi_mobile/shell/top_nav.dart';

import '../support/fake_auth.dart';
import '../support/real_fonts.dart';

/// Simulates the Android back button (WidgetsBinding.handlePopRoute, what
/// the engine calls on a back press) for every rule decided on 2026-10-14.
/// "Exits the app" = the framework calls SystemNavigator.pop.
///
/// Not testable here: with the keyboard open, Android's input method
/// consumes the first back press itself and only hides the keyboard; the
/// app never sees it.
void main() {
  useRealFonts();

  late List<String> exits;

  Future<void> settle(WidgetTester tester) async {
    // Fixed frames (some screens animate forever, so no pumpAndSettle).
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<FakeAuthService> pumpApp(
    WidgetTester tester, {
    bool signedIn = true,
    bool onboarded = true,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400); // 360x800dp
    addTearDown(tester.view.reset);
    exits = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') exits.add('exit');
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final auth = FakeAuthService(
      fakeUser: signedIn ? const KoiUser(uid: 'u1', isAnonymous: true) : null,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: overridesFor(auth, onboardingStore(complete: onboarded)),
        child: const MaterialApp(home: RootRouter()),
      ),
    );
    await settle(tester);
    return auth;
  }

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await settle(tester);
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await settle(tester);
  }

  /// For the landing / info pages, whose fixed nav covers the top 64px.
  Future<void> tapMid(WidgetTester tester, Finder f) async {
    Scrollable.ensureVisible(tester.element(f), alignment: 0.5);
    await settle(tester);
    await tester.tap(f);
    await settle(tester);
  }

  group('signed-in shell tabs', () {
    testWidgets('Chat tab: back exits the app', (tester) async {
      await pumpApp(tester);
      expect(find.byType(ChatScreen), findsOneWidget);
      await back(tester);
      expect(exits, ['exit']);
    });

    testWidgets('Progress tab: back goes to Chat, then exits', (tester) async {
      await pumpApp(tester);
      await tap(tester, find.byKey(const Key('nav-tab-progress')));
      expect(find.byType(ProgressScreen), findsOneWidget);
      await back(tester);
      expect(exits, isEmpty);
      expect(find.byType(ChatScreen), findsOneWidget);
      await back(tester);
      expect(exits, ['exit']);
    });

    testWidgets('Settings tab: back goes to Chat', (tester) async {
      await pumpApp(tester);
      await tap(tester, find.byKey(const Key('nav-tab-settings')));
      expect(find.byType(SettingsScreen), findsOneWidget);
      await back(tester);
      expect(exits, isEmpty);
      expect(find.byType(ChatScreen), findsOneWidget);
    });

    for (final (row, page) in [
      ('row-encryption', PrivacyScreen),
      ('row-data', PrivacyScreen),
      ('row-export', ExportScreen),
      ('row-import', ImportScreen),
    ]) {
      testWidgets('$page (from $row): back goes to Settings, not Chat', (
        tester,
      ) async {
        await pumpApp(tester);
        await tap(tester, find.byKey(const Key('nav-tab-settings')));
        await tap(tester, find.byKey(Key(row)));
        expect(find.byType(page), findsOneWidget);
        await back(tester);
        expect(exits, isEmpty);
        expect(find.byType(page), findsNothing);
        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(find.byType(ChatScreen), findsNothing);
        // Then Settings → Chat.
        await back(tester);
        expect(find.byType(ChatScreen), findsOneWidget);
        expect(exits, isEmpty);
      });
    }

    testWidgets('Settings popup (companion picker): back closes only it', (
      tester,
    ) async {
      await pumpApp(tester);
      await tap(tester, find.byKey(const Key('nav-tab-settings')));
      await tap(tester, find.byKey(const Key('row-avatar')));
      expect(find.byType(AvatarPicker), findsOneWidget);
      await back(tester);
      expect(exits, isEmpty);
      expect(find.byType(AvatarPicker), findsNothing);
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('tapping a tab after back still works (state not stuck)', (
      tester,
    ) async {
      await pumpApp(tester);
      await tap(tester, find.byKey(const Key('nav-tab-settings')));
      await tap(tester, find.byKey(const Key('row-export')));
      await back(tester); // → Settings
      await back(tester); // → Chat
      await tap(tester, find.byKey(const Key('nav-tab-settings')));
      // Settings opens at its root page again.
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(ExportScreen), findsNothing);
      expect(find.byType(KoiTopNav), findsOneWidget);
    });
  });

  group('landing and info pages (signed out)', () {
    testWidgets('Landing: back exits the app', (tester) async {
      await pumpApp(tester, signedIn: false);
      expect(find.byType(LandingScreen), findsOneWidget);
      await back(tester);
      expect(exits, ['exit']);
    });

    testWidgets('About: back returns to the landing page', (tester) async {
      await pumpApp(tester, signedIn: false);
      await tapMid(tester, find.byKey(const Key('footer-About')));
      expect(find.byType(AboutScreen), findsOneWidget);
      await back(tester);
      expect(exits, isEmpty);
      expect(find.byType(AboutScreen), findsNothing);
      expect(find.byType(LandingScreen), findsOneWidget);
    });

    testWidgets('How It Works → About: back walks back one page at a time', (
      tester,
    ) async {
      await pumpApp(tester, signedIn: false);
      await tapMid(tester, find.byKey(const Key('landing-how-it-works')));
      expect(find.byType(HowItWorksScreen), findsOneWidget);
      await tapMid(tester, find.byKey(const Key('footer-About')));
      expect(find.byType(AboutScreen), findsOneWidget);

      await back(tester);
      expect(find.byType(AboutScreen), findsNothing);
      expect(find.byType(HowItWorksScreen), findsOneWidget);
      await back(tester);
      expect(find.byType(HowItWorksScreen), findsNothing);
      expect(find.byType(LandingScreen), findsOneWidget);
      expect(exits, isEmpty);
    });
  });

  group('onboarding', () {
    test('previous step mirrors the forward path (Q8 skip kept)', () {
      expect(OnboardingScreen.previousStep(0), isNull); // Welcome
      expect(OnboardingScreen.previousStep(1), 0);
      expect(OnboardingScreen.previousStep(2), 1);
      expect(OnboardingScreen.previousStep(3), 2);
      expect(OnboardingScreen.previousStep(4), 3); // unreachable Avatar
      expect(OnboardingScreen.previousStep(5), 3); // Language → AI Disclosure
      expect(OnboardingScreen.previousStep(6), 5);
    });

    Future<void> pumpStep(WidgetTester tester, int step) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(1080, 2400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: overridesFor(
            FakeAuthService(
              fakeUser: const KoiUser(uid: 'u1', isAnonymous: true),
            ),
            onboardingStore(),
          ),
          child: MaterialApp(home: OnboardingScreen(initialStep: step)),
        ),
      );
      await settle(tester);
    }

    testWidgets('back walks Notification → Language → AI Disclosure → '
        'Companion → Privacy → Welcome (never Avatar)', (tester) async {
      await pumpStep(tester, 6);
      for (final expected in [
        LanguageStep,
        AIDisclosureStep,
        CompanionSelectionStep,
        PrivacyStep,
        WelcomeStep,
      ]) {
        await back(tester);
        expect(find.byType(expected), findsOneWidget, reason: '$expected');
        expect(find.byType(AvatarStep), findsNothing);
      }
    });

    testWidgets('Welcome: back signs out and shows the landing page', (
      tester,
    ) async {
      final auth = await pumpApp(tester, onboarded: false);
      expect(find.byType(WelcomeStep), findsOneWidget);
      await back(tester);
      expect(auth.signOutCalls, 1);
      expect(exits, isEmpty);
      expect(find.byType(LandingScreen), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
    });

    testWidgets('time picker popup: back closes only the picker', (
      tester,
    ) async {
      await pumpStep(tester, 6);
      await tap(tester, find.byKey(const Key('notif-time')));
      expect(find.byType(Dialog), findsOneWidget);
      await back(tester);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(NotificationStep), findsOneWidget);
    });
  });
}
