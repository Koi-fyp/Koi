import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../landing/landing_screen.dart';
import '../onboarding/onboarding_screen.dart';
import '../screens/splash_screen.dart';
import '../shell/app_shell.dart';
import 'providers.dart';

/// Where the app should be, given auth + onboarding state.
enum RootRoute { splash, landing, onboarding, chat }

/// Mirrors the redirect logic of repos/koi-backend/nextjs_app/src/app/page.tsx
/// (signed in → isOnboardingComplete() ? '/chat' : '/onboarding') and
/// (authenticated)/layout.tsx (splash while loading; signed out → '/').
///
/// The splash shows while the saved session is first restored. After that,
/// like web (decided 2026-10-13): signed out → the landing page, even while
/// signing in (its buttons show "Getting ready…"); signed in + loading → the
/// layout.tsx splash.
RootRoute resolveRootRoute({
  required bool restored,
  required bool loading,
  required bool signedIn,
  required bool onboardingComplete,
}) {
  if (!restored) return RootRoute.splash;
  if (!signedIn) return RootRoute.landing;
  if (loading) return RootRoute.splash;
  return onboardingComplete ? RootRoute.chat : RootRoute.onboarding;
}

class RootRouter extends ConsumerWidget {
  const RootRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authServiceProvider);
    final onboarding = ref.watch(onboardingStoreProvider);
    // Keeps the /health warm-up alive from app start (it fires on sign-in).
    ref.listen(backendWarmupProvider, (_, _) {});
    final route = resolveRootRoute(
      restored: auth.sessionRestored,
      loading: auth.loading,
      signedIn: auth.user != null,
      onboardingComplete: onboarding.isCompleteFor(auth.user?.uid),
    );
    // Web uses router.replace(): no back-stack between these states, so the
    // root simply swaps its child.
    return switch (route) {
      RootRoute.splash => const SplashScreen(),
      RootRoute.landing => const LandingScreen(),
      RootRoute.onboarding => const OnboardingScreen(),
      RootRoute.chat => const AppShell(),
    };
  }
}
