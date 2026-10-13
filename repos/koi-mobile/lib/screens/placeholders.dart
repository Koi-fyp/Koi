import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../theme/koi_colors.dart';
import '../theme/koi_text.dart';
import '../widgets/neo_button.dart';
import '../widgets/neo_spinner.dart';

/// PLACEHOLDER screens so routing and the shell can be exercised. The real
/// screens come in later prompts (Landing/Onboarding: Prompt 5, Chat: 6,
/// Settings: 7, Progress: 8).
///
/// Strings marked "developer label" are not product copy and are never meant
/// to ship. Strings marked with a web source are copied word for word.

class _PlaceholderBody extends StatelessWidget {
  const _PlaceholderBody({required this.title, this.children = const []});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: KoiColors.background,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title, // developer label
              textAlign: TextAlign.center,
              style: KoiText.display(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: KoiColors.neoBlack,
              ),
            ),
            for (final c in children) ...[const SizedBox(height: 16), c],
          ],
        ),
      ),
    ),
  );
}

class ChatPlaceholder extends StatelessWidget {
  const ChatPlaceholder({super.key});
  @override
  Widget build(BuildContext context) =>
      const _PlaceholderBody(title: 'Chat (placeholder — Prompt 6)');
}

class ProgressPlaceholder extends StatelessWidget {
  const ProgressPlaceholder({super.key});
  @override
  Widget build(BuildContext context) =>
      const _PlaceholderBody(title: 'Progress (placeholder — Prompt 8)');
}

class SettingsPlaceholder extends ConsumerWidget {
  const SettingsPlaceholder({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _PlaceholderBody(
    title: 'Settings (placeholder — Prompt 7)',
    children: [
      if (kDebugMode)
        NeoButton(
          key: const Key('debug-sign-out'),
          variant: NeoButtonVariant.ghost,
          onPressed: () => ref.read(authServiceProvider).signOut(),
          child: const Text('Sign out (debug)'), // developer label
        ),
    ],
  );
}

/// Landing placeholder. Only the hero call-to-action is mirrored, so sign-in
/// can be tested; copy and states are from the hero CTA block of
/// repos/koi-backend/nextjs_app/src/app/page.tsx (`hero-stagger-5`).
class LandingPlaceholder extends ConsumerStatefulWidget {
  const LandingPlaceholder({super.key});

  // page.tsx hero CTA strings
  static const String startLabel = "Start Talking — It's Free ✦";
  static const String startingLabel = 'Getting ready…';
  static const String errorText =
      '⚠ Connection failed. Check your network and try again.';
  static const String retryLabel = 'Try Again';
  static const String retryingLabel = 'Connecting…';

  @override
  ConsumerState<LandingPlaceholder> createState() => _LandingPlaceholderState();
}

class _LandingPlaceholderState extends ConsumerState<LandingPlaceholder> {
  bool _starting = false; // page.tsx `starting`

  // page.tsx handleGetStarted. Web only resets `starting` if
  // signInAnonymously() throws; AuthContext never rethrows, so `starting`
  // stays true after a failure there. Mirrored as-is.
  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      await ref.read(authServiceProvider).signInAnonymously();
    } catch (_) {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authServiceProvider);
    final isLoading = _starting || auth.loading; // page.tsx isLoading
    final showError = auth.error != null && auth.user == null;

    return Scaffold(
      backgroundColor: KoiColors.background,
      body: _PlaceholderBody(
        title: 'Landing (placeholder — Prompt 5)',
        children: [
          if (showError) ...[
            Text(
              LandingPlaceholder.errorText,
              textAlign: TextAlign.center,
              // text-sm font-semibold text-red-500 (Tailwind red-500 #ef4444)
              style: KoiText.body(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFEF4444),
              ),
            ),
            NeoButton(
              key: const Key('landing-start'),
              onPressed: isLoading ? null : _start,
              child: Text(
                isLoading
                    ? LandingPlaceholder.retryingLabel
                    : LandingPlaceholder.retryLabel,
              ),
            ),
          ] else
            NeoButton(
              key: const Key('landing-start'),
              onPressed: isLoading ? null : _start,
              child: isLoading
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        NeoSpinner(color: KoiColors.neoWhite),
                        SizedBox(width: 8), // gap-2
                        Text(LandingPlaceholder.startingLabel),
                      ],
                    )
                  : const Text(LandingPlaceholder.startLabel),
            ),
        ],
      ),
    );
  }
}

class OnboardingPlaceholder extends ConsumerWidget {
  const OnboardingPlaceholder({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    backgroundColor: KoiColors.background,
    body: _PlaceholderBody(
      title: 'Onboarding (placeholder — Prompt 5)',
      children: [
        NeoButton(
          key: const Key('debug-complete-onboarding'),
          onPressed: () => ref.read(onboardingStoreProvider).markComplete(),
          child: const Text('Mark onboarding complete'), // developer label
        ),
      ],
    ),
  );
}
