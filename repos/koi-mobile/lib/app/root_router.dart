import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/placeholders.dart';
import '../screens/splash_screen.dart';
import '../shell/app_shell.dart';
import 'providers.dart';

/// Where the app should be, given auth + onboarding state.
enum RootRoute { splash, landing, onboarding, chat }

/// Mirrors the redirect logic of repos/koi-backend/nextjs_app/src/app/page.tsx
/// (signed in → isOnboardingComplete() ? '/chat' : '/onboarding') and
/// (authenticated)/layout.tsx (splash while loading; signed out → '/').
///
/// One deliberate difference, per the Prompt 4 spec: web's '/' renders the
/// landing page while auth is loading; mobile shows the layout.tsx splash for
/// every loading state.
RootRoute resolveRootRoute({
  required bool loading,
  required bool signedIn,
  required bool onboardingComplete,
}) {
  if (loading) return RootRoute.splash;
  if (!signedIn) return RootRoute.landing;
  return onboardingComplete ? RootRoute.chat : RootRoute.onboarding;
}

class RootRouter extends ConsumerWidget {
  const RootRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authServiceProvider);
    final onboarding = ref.watch(onboardingStoreProvider);
    final route = resolveRootRoute(
      loading: auth.loading,
      signedIn: auth.user != null,
      onboardingComplete: onboarding.isComplete,
    );
    // Web uses router.replace(): no back-stack between these states, so the
    // root simply swaps its child.
    return switch (route) {
      RootRoute.splash => const SplashScreen(),
      RootRoute.landing => const LandingPlaceholder(),
      RootRoute.onboarding => const OnboardingPlaceholder(),
      RootRoute.chat => const AppShell(),
    };
  }
}
