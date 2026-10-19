import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/koi_colors.dart';
import '../theme/koi_motion.dart';
import '../theme/koi_shadows.dart';
import '../theme/koi_text.dart';
import 'neo_card.dart';

/// Whether the system asked for reduced motion (Android "Remove
/// animations"). Every MOB-1 animation checks this and shows its end state
/// instead.
bool koiReduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// The ONE KOI loader (BATCH MOB-1): the splash "K" logo square
/// (screens/splash_screen.dart: neo-blue, black border, 4px hard shadow)
/// bobbing with floatY, over three pulseDot dots. With reduced motion it is
/// completely still.
///
/// Screen readers hear [semanticsLabel] (or [label], or "Loading"), as a
/// live region so a change of step is announced.
class KoiLoader extends StatefulWidget {
  const KoiLoader({
    super.key,
    this.label,
    this.semanticsLabel,
    this.compact = false,
  });

  /// Shown under the logo (beside it when [compact]).
  final String? label;
  final String? semanticsLabel;

  /// A 20dp logo in a row with the label and no dots, for inline states
  /// such as "Saving…".
  final bool compact;

  static const double size = 44; // SplashScreen.size
  static const double compactSize = 20;
  static const double dot = 6;

  /// 'float-fast' period (3 s), without its 1.4 s delay.
  static const Duration period = Duration(seconds: 3);

  @override
  State<KoiLoader> createState() => _KoiLoaderState();
}

class _KoiLoaderState extends State<KoiLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: KoiLoader.period,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (koiReduceMotion(context)) {
      _c
        ..stop()
        ..value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _logo(double side) {
    final scale = side / KoiLoader.size;
    return Container(
      width: side,
      height: side,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: KoiColors.neoBlue,
        borderRadius: BorderRadius.circular(10 * scale),
        border: Border.all(width: 2.5 * scale),
        boxShadow: KoiShadows.hard(4 * scale),
      ),
      child: Text(
        'K',
        style: KoiText.display(
          fontWeight: FontWeight.w800,
          fontSize: 19.2 * scale,
          color: KoiColors.neoWhite,
          height: 1,
        ),
      ),
    );
  }

  Widget _dots() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < 3; i++)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, child) => Opacity(
              // Staggered by a third of the cycle each.
              opacity: _c.isAnimating
                  ? KoiMotion.pulseDotTween.transform((_c.value + i / 3) % 1)
                  : 1,
              child: child,
            ),
            child: Container(
              width: KoiLoader.dot,
              height: KoiLoader.dot,
              decoration: const BoxDecoration(
                color: KoiColors.neoBlack,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    final logo = AnimatedBuilder(
      animation: _c,
      builder: (_, child) => Transform.translate(
        offset: Offset(
          0,
          _c.isAnimating
              ? KoiMotion.floatYTween.transform(_c.value) *
                    (widget.compact ? 0.25 : 0.5)
              : 0,
        ),
        child: child,
      ),
      child: _logo(widget.compact ? KoiLoader.compactSize : KoiLoader.size),
    );
    final text = label == null
        ? null
        : Text(
            label,
            textAlign: TextAlign.center,
            style: KoiText.body(
              fontSize: widget.compact ? 13 : 15,
              fontWeight: FontWeight.w600,
              color: KoiColors.neoBlack,
              letterSpacing: 0,
            ),
          );
    return Semantics(
      key: const Key('koi-loader'),
      container: true,
      liveRegion: true,
      label: widget.semanticsLabel ?? label ?? 'Loading',
      excludeSemantics: true,
      child: widget.compact
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                logo,
                if (text != null) ...[const SizedBox(width: 8), text],
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                logo,
                const SizedBox(height: 16),
                _dots(),
                if (text != null) ...[const SizedBox(height: 12), text],
              ],
            ),
    );
  }
}

/// A full page on the KOI background with a centred [KoiLoader]. After
/// [wakingAfter] it adds the chat's cold-start wording ("KOI is waking
/// up…", chat_widgets.dart WakingLine) since the platform server may be
/// starting.
class KoiLoadingPage extends StatefulWidget {
  const KoiLoadingPage({
    super.key,
    required this.label,
    this.wakingAfter = const Duration(seconds: 4),
    this.background = KoiColors.background,
  });

  final String label;
  final Duration? wakingAfter;
  final Color background;

  static const String wakingText = 'KOI is waking up… this can take a minute.';

  @override
  State<KoiLoadingPage> createState() => _KoiLoadingPageState();
}

class _KoiLoadingPageState extends State<KoiLoadingPage> {
  Timer? _timer;
  bool _waking = false;

  @override
  void initState() {
    super.initState();
    final after = widget.wakingAfter;
    if (after != null) {
      _timer = Timer(after, () {
        if (mounted) setState(() => _waking = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: widget.background,
    child: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              KoiLoader(label: widget.label),
              if (_waking)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    KoiLoadingPage.wakingText,
                    key: const Key('koi-loader-waking'),
                    textAlign: TextAlign.center,
                    style: KoiText.body(
                      fontSize: 13,
                      color: KoiColors.koiDark,
                      letterSpacing: 0,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Skeleton placeholders for lists: [count] Neo cards with grey bars that
/// pulse (pulseDot) unless reduced motion is on.
class NeoSkeletonList extends StatefulWidget {
  const NeoSkeletonList({super.key, this.count = 3, this.label = 'Loading'});

  final int count;
  final String label;

  @override
  State<NeoSkeletonList> createState() => _NeoSkeletonListState();
}

class _NeoSkeletonListState extends State<NeoSkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: KoiMotion.pulseDot.duration,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (koiReduceMotion(context)) {
      _c
        ..stop()
        ..value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _bar(double widthFactor, double height) => FractionallySizedBox(
    widthFactor: widthFactor,
    alignment: AlignmentDirectional.centerStart,
    child: Container(
      height: height,
      decoration: BoxDecoration(
        color: KoiColors.neoGray,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Semantics(
    key: const Key('neo-skeleton'),
    label: widget.label,
    liveRegion: true,
    excludeSemantics: true,
    child: AnimatedBuilder(
      animation: _c,
      builder: (_, child) => Opacity(
        opacity: _c.isAnimating
            ? KoiMotion.pulseDotTween.transform(_c.value)
            : 1,
        child: child,
      ),
      child: Column(
        children: [
          for (var i = 0; i < widget.count; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: NeoCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _bar(0.6, 16),
                    const SizedBox(height: 10),
                    _bar(0.9, 12),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
