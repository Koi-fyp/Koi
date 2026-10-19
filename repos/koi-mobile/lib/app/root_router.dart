import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_controller.dart' show UnlockState;
import '../account/account_gate_screens.dart';
import '../account/account_providers.dart';
import '../account/capability_controller.dart';
import '../landing/landing_screen.dart';
import '../questionnaires/questionnaire_providers.dart';
import '../onboarding/onboarding_screen.dart';
import '../screens/splash_screen.dart';
import '../shell/app_shell.dart';
import 'providers.dart';

/// Where the app should be, given auth + onboarding state.
enum RootRoute {
  splash,
  landing,
  onboarding,
  chat,

  // MOB-1 (registered accounts only):
  /// Default-deny loader while capabilities are confirmed.
  capabilityCheck,

  /// Portal link + sign out; never the companion or a patient screen.
  psychologist,

  /// New device / cleared cache: the password opens the history.
  unlock,

  /// Re-encrypting after linking (resumes after a restart).
  migrating,

  /// "Bring this device's KOI history into this account?"
  claim,

  /// The patient relationship ended.
  accessEnded,
}

/// Mirrors the redirect logic of repos/koi-backend/nextjs_app/src/app/page.tsx
/// (signed in → isOnboardingComplete() ? '/chat' : '/onboarding') and
/// (authenticated)/layout.tsx (splash while loading; signed out → '/').
///
/// The splash shows while the saved session is first restored. After that,
/// like web (decided 2026-10-13): signed out → the landing page, even while
/// signing in (its buttons show "Getting ready…"); signed in + loading → the
/// layout.tsx splash.
///
/// MOB-1, registered (non-anonymous) users only, in this order: capability
/// check (default-deny) → psychologist landing → unlock → migration →
/// claim → access ended → the usual onboarding / chat. An anonymous user
/// never gets past the original four routes.
RootRoute resolveRootRoute({
  required bool restored,
  required bool loading,
  required bool signedIn,
  required bool onboardingComplete,
  bool registered = false,
  CapabilityStatus capabilities = CapabilityStatus.anonymous,
  bool psychologist = false,
  UnlockState unlock = UnlockState.notNeeded,
  bool migrating = false,
  bool claimOffered = false,
  bool accessEnded = false,
}) {
  if (!restored) return RootRoute.splash;
  if (!signedIn) return RootRoute.landing;
  if (loading) return RootRoute.splash;
  if (registered) {
    if (capabilities == CapabilityStatus.loading) {
      return RootRoute.capabilityCheck;
    }
    if (psychologist) return RootRoute.psychologist;
    if (unlock == UnlockState.checking) return RootRoute.splash;
    if (unlock == UnlockState.needed) return RootRoute.unlock;
    if (migrating) return RootRoute.migrating;
    if (claimOffered) return RootRoute.claim;
    if (accessEnded) return RootRoute.accessEnded;
  }
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
    ref.listen(questionnaireCleanupProvider, (_, _) {});
    final caps = ref.watch(capabilityControllerProvider);
    final account = ref.watch(accountControllerProvider);
    final user = auth.user;
    final route = resolveRootRoute(
      restored: auth.sessionRestored,
      loading: auth.loading,
      signedIn: user != null,
      onboardingComplete: onboarding.isCompleteFor(user?.uid),
      registered: user != null && !user.isAnonymous,
      capabilities: caps.status,
      psychologist: caps.effective.isPsychologist,
      unlock: account.unlock,
      migrating: account.migrationPending,
      claimOffered: account.claimOffered,
      accessEnded: caps.accessEnded,
    );
    // Web uses router.replace(): no back-stack between these states, so the
    // root simply swaps its child.
    return switch (route) {
      RootRoute.splash => const SplashScreen(),
      RootRoute.landing => const LandingScreen(),
      RootRoute.onboarding => const OnboardingScreen(),
      // Keyed by uid: an account switch rebuilds the whole shell, so no
      // tab, nested route or form state of the previous account survives.
      RootRoute.chat => AppShell(key: ValueKey('shell-${user?.uid}')),
      RootRoute.capabilityCheck => const CapabilityCheckScreen(),
      RootRoute.psychologist => const PsychologistLandingScreen(),
      RootRoute.unlock => const UnlockScreen(),
      RootRoute.migrating => const MigrationScreen(),
      RootRoute.claim => const ClaimScreen(),
      RootRoute.accessEnded => const AccessEndedScreen(),
    };
  }
}
