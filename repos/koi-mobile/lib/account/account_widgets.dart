import 'package:flutter/material.dart';

import '../chat/widgets/chat_widgets.dart' show StrokeIcon;
import '../platform/demo_badge.dart';
import '../settings/widgets/settings_widgets.dart' show backArrowPaths;
import '../theme/koi_colors.dart';
import '../theme/koi_motion.dart';
import '../theme/koi_shadows.dart';
import '../theme/koi_text.dart';
import '../widgets/koi_loader.dart';
import '../widgets/neo_button.dart';
import '../widgets/neo_card.dart';

// Shared building blocks for the MOB-1 screens, made ONLY from the KOI
// design system (KoiColors, KoiShadows, KoiRadii, KoiText, KoiMotion, Neo
// widgets). Text colours are neoBlack / koiDark / danger on white or the
// #FFE5D9 background (all ≥ 4.5:1).

/// Minimum touch target for new controls (Material / WCAG guidance).
const double koiMinTouch = 48;

/// Page heading: Bricolage Grotesque 800 (web .neo-display).
TextStyle koiTitleStyle([double size = 28]) => KoiText.display(
  fontSize: size,
  fontWeight: FontWeight.w800,
  color: KoiColors.neoBlack,
  height: 1.15,
  letterSpacing: -0.02 * size,
);

/// Running text: DM Sans, preflight line-height 1.5.
TextStyle koiBodyStyle({
  double size = 15,
  FontWeight weight = FontWeight.w400,
  Color color = KoiColors.neoBlack,
}) => KoiText.body(
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: 1.5,
  letterSpacing: 0,
);

/// Secondary text (koiDark #2D1B2E: 13.9:1 on the KOI background).
TextStyle koiMutedStyle([double size = 13.5]) =>
    koiBodyStyle(size: size, color: KoiColors.koiDark);

/// Pushes [page] with the KoiMotion slideRight (0.5 s ease) transition, or
/// instantly when the system asks for reduced motion.
Future<T?> pushKoiPage<T>(BuildContext context, Widget page) {
  final reduce = koiReduceMotion(context);
  return Navigator.of(context).push<T>(
    PageRouteBuilder<T>(
      transitionDuration: reduce
          ? Duration.zero
          : KoiMotion.slideRight.duration,
      reverseTransitionDuration: reduce
          ? Duration.zero
          : KoiMotion.slideRight.duration,
      pageBuilder: (context, _, _) => page,
      transitionsBuilder: (context, animation, _, child) {
        if (koiReduceMotion(context)) return child;
        final t = KoiMotion.easeProgress.animate(animation);
        return AnimatedBuilder(
          animation: t,
          builder: (_, c) => Opacity(
            opacity: t.value,
            child: Transform.translate(
              offset: Offset(KoiMotion.slideRightFromDx * (1 - t.value), 0),
              child: c,
            ),
          ),
          child: child,
        );
      },
    ),
  );
}

/// A full KOI page: background, safe area, scrolling column with the
/// standard 20dp gutter, optional back button and "Demo data" badge.
class KoiPage extends StatelessWidget {
  const KoiPage({
    super.key,
    required this.children,
    this.title,
    this.back = false,
    this.backLabel = 'Back',
    this.demo = false,
    this.scroll = true,
  });

  final String? title;
  final List<Widget> children;
  final bool back;
  final String backLabel;

  /// Content from a mock adapter: shows [DemoDataBadge].
  final bool demo;
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (back || demo)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  if (back) KoiBackButton(label: backLabel),
                  const Spacer(),
                  if (demo) const DemoDataBadge(),
                ],
              ),
            ),
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Semantics(
                header: true,
                child: Text(title!, style: koiTitleStyle()),
              ),
            ),
          ...children,
        ],
      ),
    );
    return Scaffold(
      backgroundColor: KoiColors.background,
      body: SafeArea(child: scroll ? SingleChildScrollView(child: body) : body),
    );
  }
}

/// The Settings "Back" button look (BackButton.tsx: white, 2.5px border,
/// radius 12, 3px hard shadow) with any label and a 48dp touch target.
class KoiBackButton extends StatefulWidget {
  const KoiBackButton({super.key, this.label = 'Back', this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  State<KoiBackButton> createState() => _KoiBackButtonState();
}

class _KoiBackButtonState extends State<KoiBackButton> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.label,
    excludeSemantics: true,
    child: GestureDetector(
      key: const Key('koi-back'),
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap ?? () => Navigator.of(context).maybePop(),
      child: AnimatedContainer(
        duration: koiReduceMotion(context)
            ? Duration.zero
            : const Duration(milliseconds: 150),
        curve: Curves.ease,
        constraints: const BoxConstraints(minHeight: koiMinTouch),
        transform: Matrix4.translationValues(0, _down ? 1 : 0, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: KoiColors.neoWhite,
          border: Border.all(width: 2.5),
          borderRadius: BorderRadius.circular(12),
          boxShadow: KoiShadows.hard(_down ? 1 : 3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StrokeIcon(
              paths: backArrowPaths,
              size: 16,
              strokeWidth: 2.5,
              color: KoiColors.neoBlack,
            ),
            const SizedBox(width: 8),
            Text(
              widget.label,
              style: koiBodyStyle(size: 14.4, weight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A Neo card with a short message (info, empty and error states).
class KoiNoticeCard extends StatelessWidget {
  const KoiNoticeCard({
    super.key,
    required this.message,
    this.title,
    this.action,
    this.actionLabel,
    this.yellow = false,
  });

  final String? title;
  final String message;
  final VoidCallback? action;
  final String? actionLabel;
  final bool yellow;

  @override
  Widget build(BuildContext context) => NeoCard(
    variant: yellow ? NeoCardVariant.yellow : NeoCardVariant.normal,
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              title!,
              style: koiBodyStyle(size: 16, weight: FontWeight.w700),
            ),
          ),
        Text(message, style: koiBodyStyle(size: 14.5)),
        if (action != null && actionLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: NeoButton(
              key: const Key('notice-action'),
              variant: NeoButtonVariant.ghost,
              onPressed: action,
              child: Text(actionLabel!),
            ),
          ),
      ],
    ),
  );
}

/// An error line announced to screen readers.
class KoiErrorText extends StatelessWidget {
  const KoiErrorText(this.text, {super.key});
  final String text;

  /// The danger red is only the bar: red text on the KOI background would
  /// be below 4.5:1, so the words stay black.
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 4,
            decoration: BoxDecoration(
              color: KoiColors.danger,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              key: const Key('koi-error'),
              style: koiBodyStyle(size: 14, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );
}
