import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../onboarding/step_layout.dart';
import '../theme/koi_colors.dart';
import '../widgets/neo_card.dart';

/// One entry of `BLOCKS` in page.tsx.
@immutable
class ColorBlock {
  const ColorBlock(this.bg, this.text, this.label, {required this.wide});
  final Color bg;
  final Color text;
  final String label;
  final bool wide;
}

/// page.tsx `ColorGrid()`: a 3-column grid of bouncing colour blocks with a
/// blurred blue glow, a rotated yellow "🐟 Meet KOI" tag and an "∞" card.
///
/// Tailwind: 1 unit = 4px; text-xs 0.75rem/1rem; text-2xl 1.5rem/2rem;
/// tracking-widest 0.1em; tracking-tight -0.025em; rotate-6 = 6deg.
class ColorGrid extends StatelessWidget {
  const ColorGrid({super.key});

  static const List<ColorBlock> blocks = [
    ColorBlock(Color(0xFF2D63EB), Color(0xFFFFFFFF), 'Think', wide: true),
    ColorBlock(Color(0xFFFFD100), Color(0xFF000000), 'Feel', wide: false),
    ColorBlock(Color(0xFFFF6B6B), Color(0xFFFFFFFF), 'Grow', wide: false),
    ColorBlock(Color(0xFF0A0A0A), Color(0xFFFFD100), 'Talk', wide: true),
    ColorBlock(Color(0xFF2DD36F), Color(0xFF000000), 'Learn', wide: true),
    ColorBlock(Color(0xFFFF9F43), Color(0xFFFFFFFF), 'Rest', wide: false),
    ColorBlock(Color(0xFF845EC2), Color(0xFFFFFFFF), 'Dream', wide: false),
    ColorBlock(Color(0xFFF4F4F4), Color(0xFF000000), 'Reflect', wide: true),
    ColorBlock(Color(0xFF2D63EB), Color(0xFFFFFFFF), 'Connect', wide: false),
    ColorBlock(Color(0xFFFFD100), Color(0xFF000000), 'Explore', wide: true),
  ];

  /// globals.css `.color-block:nth-child(n)` --rot (deg) and delay (s).
  /// The 10th block has no rule: rotation 0, delay 0.
  static const List<(double, double)> bounce = [
    (-2, 0),
    (1, 0.3),
    (-1, 0.6),
    (2, 0.9),
    (-3, 1.2),
    (1.5, 1.5),
    (-1, 0.4),
    (2.5, 0.8),
    (-2, 1.1),
    (0, 0),
  ];

  /// `height: i % 3 === 0 ? '110px' : i % 3 === 1 ? '90px' : '100px'`.
  static double heightFor(int i) => switch (i % 3) {
    0 => 110,
    1 => 90,
    _ => 100,
  };

  static const double gap = 12; // gap-3

  @override
  Widget build(BuildContext context) {
    // CSS grid auto-placement: every row is wide(2)+narrow(1) or
    // narrow(1)+wide(2), so the 10 blocks form 5 rows of 3 columns. Items
    // keep their own height and sit at the top of the row.
    return Padding(
      padding: const EdgeInsets.all(24), // padding: 1.5rem
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // absolute inset-0 rounded-3xl opacity-10 #2D63EB blur(60px)
          // scale(1.1); fills the padded box, hence the -24 insets.
          Positioned(
            left: -24,
            top: -24,
            right: -24,
            bottom: -24,
            child: IgnorePointer(
              child: Transform.scale(
                scale: 1.1,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                  child: Opacity(
                    opacity: 0.1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: KoiColors.neoBlue,
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final col = (constraints.maxWidth - 2 * gap) / 3;
              final rows = <Widget>[];
              for (var i = 0; i < blocks.length; i += 2) {
                if (i > 0) rows.add(const SizedBox(height: gap));
                rows.add(
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _block(i, col),
                      const SizedBox(width: gap),
                      _block(i + 1, col),
                    ],
                  ),
                );
              }
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Column(children: rows),
                  // absolute -top-4 -right-4 neo-card--yellow px-4 py-2
                  // text-xs font-black tracking-tight rotate-6 z-10,
                  // boxShadow 3px 3px 0 #000
                  Positioned(
                    top: -16,
                    right: -16,
                    child: Transform.rotate(
                      angle: 6 * math.pi / 180,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: KoiColors.neoYellow,
                          border: Border.all(width: 2.5),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [BoxShadow(offset: Offset(3, 3))],
                        ),
                        child: Text(
                          '🐟 Meet KOI',
                          style: bodyText(
                            12,
                            weight: FontWeight.w700,
                            letterSpacing: -0.025 * 12,
                            height: 16 / 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          // absolute -bottom-6 -left-4 neo-card px-4 py-3, minWidth 170px.
          // Positioned against the padded ColorGrid box (hence -24+-24 etc.).
          Positioned(
            left: -16 - 24,
            bottom: -24 - 24,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 170),
              child: NeoCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // text-2xl font-black text-black leading-none
                    Text(
                      '∞',
                      style: bodyText(24, weight: FontWeight.w700, height: 1),
                    ),
                    const SizedBox(height: 2), // mt-0.5
                    Text(
                      'Conversations possible',
                      style: bodyText(
                        12,
                        weight: FontWeight.w600,
                        color: const Color(0xFF6B7280),
                        height: 16 / 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _block(int i, double col) {
    final b = blocks[i];
    final (rot, delay) = bounce[i];
    return _BlockBounce(
      rotationDeg: rot,
      delay: Duration(milliseconds: (delay * 1000).round()),
      child: Container(
        width: b.wide ? 2 * col + gap : col,
        height: heightFor(i),
        alignment: Alignment.bottomLeft, // flex items-end
        padding: const EdgeInsets.all(12), // p-3
        decoration: BoxDecoration(
          color: b.bg,
          // .color-block: radius 1rem; border 2px rgba(0,0,0,0.08)
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x14000000), width: 2),
        ),
        child: Opacity(
          opacity: 0.8,
          // font-black text-xs uppercase tracking-widest opacity-80
          child: Text(
            b.label.toUpperCase(),
            style: bodyText(
              12,
              weight: FontWeight.w700,
              color: b.text,
              letterSpacing: 0.1 * 12,
              height: 16 / 12,
            ),
          ),
        ),
      ),
    );
  }
}

/// `@keyframes blockBounce`: translateY 0 → -6px → 0 with a constant
/// rotate(var(--rot)), 4s ease-in-out infinite, after `animation-delay`.
class _BlockBounce extends StatefulWidget {
  const _BlockBounce({
    required this.rotationDeg,
    required this.delay,
    required this.child,
  });

  final double rotationDeg;
  final Duration delay;
  final Widget child;

  @override
  State<_BlockBounce> createState() => _BlockBounceState();
}

class _BlockBounceState extends State<_BlockBounce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );
  bool _started = false;
  Timer? _delay;

  static final Animatable<double> _dy = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 0.0,
        end: -6.0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 50,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: -6.0,
        end: 0.0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 50,
    ),
  ]);

  @override
  void initState() {
    super.initState();
    _delay = Timer(widget.delay, () {
      _started = true;
      _c.repeat();
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, child) => Transform.translate(
      offset: Offset(0, _started ? _dy.evaluate(_c) : 0),
      child: Transform.rotate(
        angle: widget.rotationDeg * math.pi / 180,
        child: child,
      ),
    ),
    child: widget.child,
  );
}
