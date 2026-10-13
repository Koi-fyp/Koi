import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../onboarding/step_layout.dart' show bodyText;
import '../theme/koi_colors.dart';
import '../widgets/neo_button.dart';

/// Shared pieces of src/app/about/page.tsx and src/app/how-it-works/page.tsx
/// at phone width.
///
/// Conventions (as in landing_screen.dart): Tailwind 1 unit = 4px, v3.4.19
/// type scale (text-xs .75rem/1rem, text-sm .875rem/1.25rem, text-base
/// 1rem/1.5rem, text-xl 1.25rem/1.75rem, text-2xl 1.5rem/2rem, text-3xl
/// 1.875rem/2.25rem, text-4xl 2.25rem/2.5rem; leading-tight 1.25,
/// leading-relaxed 1.625; tracking-widest .1em). `font-inter` maps to DM
/// Sans (tailwind.config.ts), loaded 300–700, so font-black renders at 700.
/// Background is the solid #ffe5d9; `.grain` / `.page-bg` and every other
/// CDN image are not loaded (Q10, decision 2026-10-14).

/// Where the info pages' links go. Built by the landing page, which pushes
/// these pages (web: `<Link href="/">`, `/#faq`, `/about`, `/how-it-works`).
@immutable
class InfoLinks {
  const InfoLinks({
    required this.home,
    required this.faq,
    required this.about,
    required this.howItWorks,
  });

  final VoidCallback home;
  final VoidCallback faq;
  final VoidCallback about;
  final VoidCallback howItWorks;
}

/// The fixed top nav of both pages (same markup as the landing nav, but the
/// button is a `<Link href="/">` "Start Talking →"; the text links are
/// `hidden md:flex`, so hidden at phone width). Unscrolled: 64px, white/75;
/// scrolled (>20px): 52px, white/97 + `0 4px 0 0 #000`; backdrop-blur-md.
class InfoNav extends StatelessWidget {
  const InfoNav({
    super.key,
    required this.scrolled,
    required this.topInset,
    required this.onHome,
  });

  final bool scrolled;
  final double topInset;
  final VoidCallback onHome;

  static const Duration transition = Duration(milliseconds: 300);

  @override
  Widget build(BuildContext context) => ClipRect(
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: AnimatedContainer(
        key: const Key('info-nav'),
        duration: transition,
        curve: Curves.ease,
        height: (scrolled ? 52 : 64) + topInset,
        padding: EdgeInsets.only(top: topInset, left: 24, right: 24),
        decoration: BoxDecoration(
          color: scrolled ? const Color(0xF7FFFFFF) : const Color(0xBFFFFFFF),
          border: const Border(bottom: BorderSide(width: 2)),
          boxShadow: scrolled
              ? const [BoxShadow(offset: Offset(0, 4))]
              : const [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              key: const Key('info-nav-logo'),
              behavior: HitTestBehavior.opaque, // the gap is tappable too
              onTap: onHome,
              child: Row(
                children: [
                  // w-9 h-9 rounded-xl text-lg font-black text-white
                  // border-2 border-black, #2D63EB, 2px 2px 0 #000
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D63EB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(width: 2),
                      boxShadow: const [BoxShadow(offset: Offset(2, 2))],
                    ),
                    child: Text(
                      'K',
                      style: bodyText(
                        18,
                        weight: FontWeight.w700,
                        color: KoiColors.neoWhite,
                        height: 28 / 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10), // gap-2.5
                  Text(
                    'KOI',
                    style: bodyText(
                      18,
                      weight: FontWeight.w700,
                      letterSpacing: -0.025 * 18,
                      height: 28 / 18,
                    ),
                  ),
                ],
              ),
            ),
            NeoButton(
              key: const Key('info-nav-start'),
              customFontSize: 14, // fontSize 0.875rem
              customPadding: const EdgeInsets.symmetric(
                vertical: 8, // 0.5rem
                horizontal: 20, // 1.25rem
              ),
              onPressed: onHome,
              child: const Text('Start Talking →'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// globals.css `.neo-tag` (no dot): neo-gray, border 1.5px #e5e5e5, pill,
/// padding .3rem .875rem, .8rem 600 #333. [fontSize] / [padding] cover the
/// inline overrides on the about timeline.
class InfoNeoTag extends StatelessWidget {
  const InfoNeoTag(
    this.text, {
    super.key,
    this.fontSize = 12.8,
    this.padding = const EdgeInsets.symmetric(vertical: 4.8, horizontal: 14),
  });

  final String text;
  final double fontSize;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: KoiColors.neoGray,
      border: Border.all(color: const Color(0xFFE5E5E5), width: 1.5),
      borderRadius: BorderRadius.circular(9999),
    ),
    child: Text(
      text,
      style: bodyText(
        fontSize,
        weight: FontWeight.w600,
        color: const Color(0xFF333333),
      ),
    ),
  );
}

/// `text-xs font-black tracking-widest uppercase` eyebrow, e.g. "OUR MISSION".
class InfoEyebrow extends StatelessWidget {
  const InfoEyebrow(
    this.text, {
    super.key,
    required this.color,
    this.bottom = 16, // mb-4
  });

  final String text;
  final Color color;
  final double bottom;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: bottom),
    child: Text(
      text.toUpperCase(),
      style: bodyText(
        12,
        weight: FontWeight.w900,
        color: color,
        letterSpacing: 0.1 * 12,
        height: 16 / 12,
      ),
    ),
  );
}

/// `font-black leading-tight` heading with letter-spacing -0.03em.
TextStyle infoHeading(double size, {Color color = KoiColors.neoBlack}) =>
    bodyText(
      size,
      weight: FontWeight.w900,
      color: color,
      letterSpacing: -0.03 * size,
      height: 1.25,
    );

/// One CSS `radial-gradient(circle at X% Y%, <color>, transparent <stop>%)`
/// layer with `background-size: cover` (i.e. sized to the box).
@immutable
class CssRadial {
  const CssRadial(this.x, this.y, this.color, this.stop);
  final double x; // 0..1
  final double y; // 0..1
  final Color color;
  final double stop; // 0..1
}

/// Paints [base] and then [layers] (CSS lists the top layer first, so they
/// are painted last-to-first). `circle` without a size means
/// `farthest-corner`, so the radius is the distance to the farthest corner.
class CssRadialBackground extends CustomPainter {
  const CssRadialBackground(this.base, this.layers);
  final Color base;
  final List<CssRadial> layers;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = base);
    for (final l in layers.reversed) {
      final c = Offset(l.x * size.width, l.y * size.height);
      final r = [
        rect.topLeft,
        rect.topRight,
        rect.bottomLeft,
        rect.bottomRight,
      ].map((p) => (p - c).distance).reduce(math.max);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.radial(
            c,
            r,
            [l.color, l.color.withAlpha(0)], // CSS `transparent` (premult.)
            [0, l.stop],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(CssRadialBackground old) =>
      old.base != base || old.layers != layers;
}
