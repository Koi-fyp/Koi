import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/app/root_router.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/core/auth/debug_local_auth_service.dart';
import 'package:koi_mobile/core/key_value_store.dart';
import 'package:koi_mobile/core/onboarding_store.dart';
import 'package:koi_mobile/landing/landing_screen.dart';
import 'package:koi_mobile/onboarding/onboarding_screen.dart';
import 'package:koi_mobile/screens/placeholders.dart';
import 'package:koi_mobile/screens/splash_screen.dart';
import 'package:koi_mobile/shell/app_shell.dart';

import '../support/fake_auth.dart';
import '../support/real_fonts.dart';

const _user = KoiUser(uid: 'u1', isAnonymous: true);

void main() {
  useRealFonts();

  group('resolveRootRoute (page.tsx + (authenticated)/layout.tsx)', () {
    RootRoute r(bool loading, bool signedIn, bool complete) => resolveRootRoute(
      loading: loading,
      signedIn: signedIn,
      onboardingComplete: complete,
    );

    test('loading always shows the splash', () {
      for (final signedIn in [false, true]) {
        for (final complete in [false, true]) {
          expect(r(true, signedIn, complete), RootRoute.splash);
        }
      }
    });
    test('signed out → landing, whatever the flag says', () {
      expect(r(false, false, false), RootRoute.landing);
      expect(r(false, false, true), RootRoute.landing);
    });
    test('signed in + not complete → onboarding', () {
      expect(r(false, true, false), RootRoute.onboarding);
    });
    test('signed in + complete → chat', () {
      expect(r(false, true, true), RootRoute.chat);
    });
  });

  Future<void> pumpRouter(
    WidgetTester tester,
    AuthService auth,
    OnboardingStore onboarding,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400); // Infinix X663
    tester.view.devicePixelRatio = 3; // density 480 → 360 x 800 dp
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overridesFor(auth, onboarding),
        child: const MaterialApp(home: RootRouter()),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('loading → splash', (tester) async {
    await pumpRouter(
      tester,
      FakeAuthService(fakeLoading: true),
      onboardingStore(),
    );
    expect(find.byType(SplashScreen), findsOneWidget);
  });

  testWidgets('signed out → landing; Start signs in → onboarding', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await pumpRouter(tester, auth, onboardingStore());
    expect(find.byType(LandingScreen), findsOneWidget);
    expect(find.text(LandingScreen.startLabel), findsOneWidget);

    await tester.tap(find.byKey(const Key('landing-start')));
    await tester.pump(const Duration(seconds: 1));
    expect(auth.signInCalls, 1);
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets('sign-in error shows the web error copy and Try Again', (
    tester,
  ) async {
    await pumpRouter(
      tester,
      FakeAuthService(fakeError: Exception('x')),
      onboardingStore(),
    );
    expect(find.text(LandingScreen.errorText), findsOneWidget);
    expect(find.text(LandingScreen.retryLabel), findsOneWidget);
  });

  testWidgets(
    'signed in + not complete → onboarding; completing → chat shell',
    (tester) async {
      final onboarding = onboardingStore();
      await pumpRouter(tester, FakeAuthService(fakeUser: _user), onboarding);
      expect(find.byType(OnboardingScreen), findsOneWidget);

      await onboarding.markComplete(); // the last onboarding step's effect
      await tester.pump(const Duration(seconds: 1));
      expect(onboarding.isComplete, isTrue);
      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(ChatPlaceholder), findsOneWidget);
    },
  );

  testWidgets('signed in + complete → chat; sign out → landing, flag kept', (
    tester,
  ) async {
    final auth = FakeAuthService(fakeUser: _user);
    final onboarding = onboardingStore(complete: true);
    await pumpRouter(tester, auth, onboarding);
    expect(find.byType(ChatPlaceholder), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav-tab-settings')));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const Key('debug-sign-out')));
    await tester.pump(const Duration(seconds: 1));

    expect(auth.signOutCalls, 1);
    expect(find.byType(LandingScreen), findsOneWidget);
    expect(onboarding.isComplete, isTrue); // web never clears it on sign-out
  });

  testWidgets('with the debug stand-in: splash, then restored user → chat', (
    tester,
  ) async {
    final kv = MemoryKeyValueStore({
      DebugLocalAuthService.uidKey: 'debug-persisted',
    });
    final auth = DebugLocalAuthService(() async => kv);
    await pumpRouter(tester, auth, onboardingStore(complete: true));
    expect(find.byType(SplashScreen), findsOneWidget);

    await auth.restoreSession();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ChatPlaceholder), findsOneWidget);
  });
}
