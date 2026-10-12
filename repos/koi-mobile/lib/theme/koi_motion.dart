import 'dart:async';

import 'package:flutter/widgets.dart';

/// KOI motion, mirrored from the web keyframes and animation utilities.
///
/// Sources (repos/koi-backend/nextjs_app/):
/// - tailwind.config.ts `theme.extend.animation` / `keyframes`
/// - src/app/globals.css `@keyframes` (identical definitions)
///
/// CSS timing keywords map exactly onto Flutter curves:
///   ease        = cubic-bezier(0.25, 0.1, 0.25, 1) = Curves.ease
///   ease-in-out = cubic-bezier(0.42, 0, 0.58, 1)   = Curves.easeInOut
///   linear                                          = Curves.linear
/// CSS applies the timing function to each keyframe segment separately, so
/// multi-stop keyframes are built as TweenSequences with the curve per segment
/// and driven by a linear controller.

/// Duration/delay/repeat of one web `animation:` declaration.
@immutable
class KoiAnimationSpec {
  const KoiAnimationSpec({
    required this.duration,
    this.delay = Duration.zero,
    this.repeat = false,
  });

  final Duration duration;

  /// CSS animation-delay: applied once, before the first iteration.
  final Duration delay;

  /// `infinite` iteration count.
  final bool repeat;
}

abstract final class KoiMotion {
  // ── animation utilities (tailwind.config.ts theme.extend.animation) ─────
  /// 'float-slow': floatY 5s ease-in-out infinite
  static const floatSlow = KoiAnimationSpec(
      duration: Duration(seconds: 5), repeat: true);

  /// 'float-mid': floatY 4s ease-in-out infinite 0.7s
  static const floatMid = KoiAnimationSpec(
      duration: Duration(seconds: 4),
      delay: Duration(milliseconds: 700),
      repeat: true);

  /// 'float-fast': floatY 3s ease-in-out infinite 1.4s
  static const floatFast = KoiAnimationSpec(
      duration: Duration(seconds: 3),
      delay: Duration(milliseconds: 1400),
      repeat: true);

  /// 'spin-slow': spin 8s linear infinite
  static const spinSlow = KoiAnimationSpec(
      duration: Duration(seconds: 8), repeat: true);

  /// 'fade-up': fadeUp 0.6s ease both
  static const fadeUp = KoiAnimationSpec(duration: Duration(milliseconds: 600));

  /// 'slide-right': slideRight 0.5s ease both
  static const slideRight =
      KoiAnimationSpec(duration: Duration(milliseconds: 500));

  /// 'pulse-dot': pulseDot 2s ease-in-out infinite
  static const pulseDot = KoiAnimationSpec(
      duration: Duration(seconds: 2), repeat: true);

  /// globals.css .neo-spinner: spin 0.7s linear infinite
  static const neoSpinner = KoiAnimationSpec(
      duration: Duration(milliseconds: 700), repeat: true);

  // ── keyframes as tweens (value at controller t in 0..1) ──────────────────
  /// floatY: 0%,100% translateY(0px); 50% translateY(-12px). Value = dy px.
  static final Animatable<double> floatYTween = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween(begin: 0.0, end: -12.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50),
    TweenSequenceItem(
        tween: Tween(begin: -12.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50),
  ]);

  /// pulseDot: 0%,100% opacity 1; 50% opacity 0.4. Value = opacity.
  static final Animatable<double> pulseDotTween = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.4)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50),
    TweenSequenceItem(
        tween: Tween(begin: 0.4, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50),
  ]);

  /// fadeUp / slideRight progress (single segment, `ease`).
  static final Animatable<double> easeProgress =
      CurveTween(curve: Curves.ease);

  /// fadeUp: from opacity 0, translateY(20px) → opacity 1, translateY(0).
  static const double fadeUpFromDy = 20;

  /// slideRight: from opacity 0, translateX(-16px) → opacity 1, translateX(0).
  static const double slideRightFromDx = -16;
}

/// Drives an [AnimationController] according to a [KoiAnimationSpec].
mixin _KoiSpecAnimation<T extends StatefulWidget>
    on State<T>, SingleTickerProviderStateMixin<T> {
  late final AnimationController controller;
  Timer? _delayTimer;

  KoiAnimationSpec get spec;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(vsync: this, duration: spec.duration);
    if (spec.delay == Duration.zero) {
      _start();
    } else {
      _delayTimer = Timer(spec.delay, _start);
    }
  }

  void _start() => spec.repeat ? controller.repeat() : controller.forward();

  @override
  void dispose() {
    _delayTimer?.cancel();
    controller.dispose();
    super.dispose();
  }
}

/// `animate-float-*`: bobs [child] up 12px and back.
class KoiFloatY extends StatefulWidget {
  const KoiFloatY({
    super.key,
    required this.child,
    this.spec = KoiMotion.floatSlow,
  });

  final Widget child;
  final KoiAnimationSpec spec;

  @override
  State<KoiFloatY> createState() => _KoiFloatYState();
}

class _KoiFloatYState extends State<KoiFloatY>
    with SingleTickerProviderStateMixin, _KoiSpecAnimation {
  @override
  KoiAnimationSpec get spec => widget.spec;

  @override
  Widget build(BuildContext context) {
    final dy = KoiMotion.floatYTween.animate(controller);
    return AnimatedBuilder(
      animation: dy,
      builder: (_, child) =>
          Transform.translate(offset: Offset(0, dy.value), child: child),
      child: widget.child,
    );
  }
}

/// `animate-fade-up` / .hero-stagger-N: fades [child] in while rising 20px.
/// `both` fill mode: shows the `from` state during the delay.
class KoiFadeUp extends StatefulWidget {
  const KoiFadeUp({
    super.key,
    required this.child,
    this.spec = KoiMotion.fadeUp,
  });

  final Widget child;
  final KoiAnimationSpec spec;

  @override
  State<KoiFadeUp> createState() => _KoiFadeUpState();
}

class _KoiFadeUpState extends State<KoiFadeUp>
    with SingleTickerProviderStateMixin, _KoiSpecAnimation {
  @override
  KoiAnimationSpec get spec => widget.spec;

  @override
  Widget build(BuildContext context) {
    final t = KoiMotion.easeProgress.animate(controller);
    return AnimatedBuilder(
      animation: t,
      builder: (_, child) => Opacity(
        opacity: t.value,
        child: Transform.translate(
          offset: Offset(0, KoiMotion.fadeUpFromDy * (1 - t.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// `animate-slide-right`: fades [child] in while sliding 16px from the left.
class KoiSlideRight extends StatefulWidget {
  const KoiSlideRight({
    super.key,
    required this.child,
    this.spec = KoiMotion.slideRight,
  });

  final Widget child;
  final KoiAnimationSpec spec;

  @override
  State<KoiSlideRight> createState() => _KoiSlideRightState();
}

class _KoiSlideRightState extends State<KoiSlideRight>
    with SingleTickerProviderStateMixin, _KoiSpecAnimation {
  @override
  KoiAnimationSpec get spec => widget.spec;

  @override
  Widget build(BuildContext context) {
    final t = KoiMotion.easeProgress.animate(controller);
    return AnimatedBuilder(
      animation: t,
      builder: (_, child) => Opacity(
        opacity: t.value,
        child: Transform.translate(
          offset: Offset(KoiMotion.slideRightFromDx * (1 - t.value), 0),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// `animate-pulse-dot`: pulses [child] opacity 1 → 0.4 → 1.
class KoiPulseDot extends StatefulWidget {
  const KoiPulseDot({
    super.key,
    required this.child,
    this.spec = KoiMotion.pulseDot,
  });

  final Widget child;
  final KoiAnimationSpec spec;

  @override
  State<KoiPulseDot> createState() => _KoiPulseDotState();
}

class _KoiPulseDotState extends State<KoiPulseDot>
    with SingleTickerProviderStateMixin, _KoiSpecAnimation {
  @override
  KoiAnimationSpec get spec => widget.spec;

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: KoiMotion.pulseDotTween.animate(controller),
        child: widget.child,
      );
}

/// `animate-spin-slow` / @keyframes spin: one full turn per iteration, linear.
class KoiSpin extends StatefulWidget {
  const KoiSpin({
    super.key,
    required this.child,
    this.spec = KoiMotion.spinSlow,
  });

  final Widget child;
  final KoiAnimationSpec spec;

  @override
  State<KoiSpin> createState() => _KoiSpinState();
}

class _KoiSpinState extends State<KoiSpin>
    with SingleTickerProviderStateMixin, _KoiSpecAnimation {
  @override
  KoiAnimationSpec get spec => widget.spec;

  @override
  Widget build(BuildContext context) =>
      RotationTransition(turns: controller, child: widget.child);
}
