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
import 'package:koi_mobile/screens/splash_screen.dart';
import 'package:koi_mobile/chat/chat_screen.dart';
import 'package:koi_mobile/shell/app_shell.dart';

import '../support/fake_auth.dart';
import '../support/real_fonts.dart';

const _user = KoiUser(uid: 'u1', isAnonymous: true);

void main() {
  useRealFonts();

  group('ATC-M1-05 resolveRootRoute (page.tsx + (authenticated)/layout.tsx)', () {
    RootRoute r(
      bool loading,
      bool signedIn,
      bool complete, {
      bool restored = true,
    }) => resolveRootRoute(
      restored: restored,
      loading: loading,
      signedIn: signedIn,
      onboardingComplete: complete,
    );

    test('session not restored yet → splash, whatever else', () {
      for (final loading in [false, true]) {
        for (final signedIn in [false, true]) {
          expect(r(loading, signedIn, true, restored: false), RootRoute.splash);
        }
      }
    });
    test('signing in (loading, signed out) stays on landing like web', () {
      expect(r(true, false, false), RootRoute.landing);
    });
    test('signed in + loading → layout.tsx splash', () {
      expect(r(true, true, true), RootRoute.splash);
      expect(r(true, true, false), RootRoute.splash);
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

  testWidgets('ATC-M1-06 loading → splash', (tester) async {
    await pumpRouter(
      tester,
      FakeAuthService(fakeLoading: true, fakeRestored: false),
      onboardingStore(),
    );
    expect(find.byType(SplashScreen), findsOneWidget);
  });

  testWidgets('ATC-M1-06 signed out → landing; Start signs in → onboarding', (
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

  testWidgets('ATC-M1-06 sign-in error shows the web error copy and Try Again', (
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
    'ATC-M1-07 signed in + not complete → onboarding; completing → chat shell',
    (tester) async {
      final onboarding = onboardingStore();
      await pumpRouter(tester, FakeAuthService(fakeUser: _user), onboarding);
      expect(find.byType(OnboardingScreen), findsOneWidget);

      await onboarding.markComplete('u1'); // the last onboarding step's effect
      await tester.pump(const Duration(seconds: 1));
      expect(onboarding.isCompleteFor('u1'), isTrue);
      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(ChatScreen), findsOneWidget);
    },
  );

  testWidgets('ATC-M1-07 signed in + complete → chat; sign out → landing, flag kept', (
    tester,
  ) async {
    final auth = FakeAuthService(fakeUser: _user);
    final onboarding = onboardingStore(complete: true);
    await pumpRouter(tester, auth, onboarding);
    expect(find.byType(ChatScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav-tab-settings')));
    await tester.pump(const Duration(seconds: 1));
    // Settings is a scroll view; the debug button sits at the bottom.
    await tester.ensureVisible(find.byKey(const Key('debug-sign-out')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('debug-sign-out')));
    await tester.pump(const Duration(seconds: 1));

    expect(auth.signOutCalls, 1);
    expect(find.byType(LandingScreen), findsOneWidget);
    expect(
      onboarding.isCompleteFor('u1'),
      isTrue,
    ); // web never clears it on sign-out
  });

  testWidgets('ATC-M1-07 same uid signs back in → chat (onboarding skipped)', (
    tester,
  ) async {
    final auth = FakeAuthService(fakeUser: _user);
    await pumpRouter(tester, auth, onboardingStore(complete: true));
    expect(find.byType(ChatScreen), findsOneWidget);

    auth.set(user: null);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(LandingScreen), findsOneWidget);

    auth.set(user: _user);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
  });

  testWidgets('ATC-M1-07 new uid (after sign-out or debug → Firebase) → onboarding', (
    tester,
  ) async {
    final auth = FakeAuthService(fakeUser: _user);
    final onboarding = onboardingStore(complete: true); // done for u1 only
    await pumpRouter(tester, auth, onboarding);
    expect(find.byType(ChatScreen), findsOneWidget);

    auth.set(user: null);
    await tester.pump(const Duration(seconds: 1));
    auth.set(user: const KoiUser(uid: 'u2', isAnonymous: true));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(onboarding.isCompleteFor('u2'), isFalse);
    expect(onboarding.isCompleteFor('u1'), isTrue);
  });

  testWidgets('ATC-M1-07 with the debug stand-in: splash, then restored user → chat', (
    tester,
  ) async {
    final kv = MemoryKeyValueStore({
      DebugLocalAuthService.uidKey: 'debug-persisted',
    });
    final auth = DebugLocalAuthService(() async => kv);
    await pumpRouter(
      tester,
      auth,
      onboardingStore(complete: true, uid: 'debug-persisted'),
    );
    expect(find.byType(SplashScreen), findsOneWidget);

    await auth.restoreSession();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ChatScreen), findsOneWidget);
  });
}
