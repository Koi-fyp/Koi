import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../safety/safety_providers.dart';
import 'environment_controller.dart';
import 'environment_palette.dart';

/// The signed-in user's background mood. A new controller (neutral) for each
/// user, so sign-out / another user resets it; nothing is persisted, so an
/// app restart does too. Fed with avatar events by chatControllerProvider.
final environmentControllerProvider =
    ChangeNotifierProvider<EnvironmentController>((ref) {
      final uid = ref.watch(authServiceProvider.select((a) => a.user?.uid));
      final safety = ref.read(safetyControllerProvider);
      ({bool crisis, bool breathing}) read() => (
        crisis: safety.crisis != null || safety.resolutionPending,
        breathing: safety.breathing != null,
      );
      final env = EnvironmentController(uid: uid, safetyState: read);
      void sync() {
        final s = read();
        env.updateSafety(crisis: s.crisis, breathing: s.breathing);
      }

      sync();
      safety.addListener(sync);
      ref.onDispose(() => safety.removeListener(sync));
      return env;
    });

/// The current background at [strength] for [builder], changing smoothly
/// over [EnvironmentPalette.transition], or at once when the system removes
/// animations. [child] is passed through unchanged (not rebuilt per frame).
class EnvironmentColorBuilder extends ConsumerWidget {
  const EnvironmentColorBuilder({
    super.key,
    required this.strength,
    required this.builder,
    this.child,
  });

  final double strength;
  final Widget Function(BuildContext context, Color color, Widget? child)
  builder;
  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mood = ref.watch(environmentControllerProvider.select((e) => e.mood));
    final target = EnvironmentPalette.colorFor(mood, strength);
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: target),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : EnvironmentPalette.transition,
      curve: EnvironmentPalette.curve,
      builder: (context, color, child) =>
          builder(context, color ?? target, child),
      child: child,
    );
  }
}

/// [child] on the current background at [strength].
class EnvironmentBackground extends StatelessWidget {
  const EnvironmentBackground({
    super.key,
    required this.strength,
    required this.child,
  });

  final double strength;
  final Widget child;

  @override
  Widget build(BuildContext context) => EnvironmentColorBuilder(
    strength: strength,
    builder: (context, color, child) => ColoredBox(
      key: const Key('environment-background'),
      color: color,
      child: child,
    ),
    child: child,
  );
}
