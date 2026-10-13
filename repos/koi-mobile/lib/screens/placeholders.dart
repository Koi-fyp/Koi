import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../theme/koi_colors.dart';
import '../theme/koi_text.dart';
import '../widgets/neo_button.dart';

/// PLACEHOLDER screens so routing and the shell can be exercised. The real
/// screens come in later prompts (Chat: 6,
/// Settings: 7, Progress: 8, About/How it works: 9).
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

/// About / How it works placeholders (Prompt 9), opened from the landing
/// page's About / How It Works links.
class AboutPlaceholder extends StatelessWidget {
  const AboutPlaceholder({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: KoiColors.background,
    appBar: AppBar(backgroundColor: KoiColors.background),
    body: const _PlaceholderBody(title: 'About (placeholder — Prompt 9)'),
  );
}

class HowItWorksPlaceholder extends StatelessWidget {
  const HowItWorksPlaceholder({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: KoiColors.background,
    appBar: AppBar(backgroundColor: KoiColors.background),
    body: const _PlaceholderBody(
      title: 'How it works (placeholder — Prompt 9)',
    ),
  );
}
