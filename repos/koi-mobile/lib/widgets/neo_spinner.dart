import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/koi_motion.dart';

/// Mirrors globals.css `.neo-spinner` (repos/koi-backend/nextjs_app):
/// 1rem (16px) circle, `border: 2px solid currentColor`,
/// `border-top-color: transparent`, `animation: spin 0.7s linear infinite`.
class NeoSpinner extends StatelessWidget {
  const NeoSpinner({super.key, required this.color});

  /// CSS `currentColor`: the text colour of the surrounding button.
  final Color color;

  static const double size = 16; // 1rem
  static const double strokeWidth = 2;

  @override
  Widget build(BuildContext context) => KoiSpin(
        spec: KoiMotion.neoSpinner,
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(painter: _SpinnerPainter(color)),
        ),
      );
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // A CSS border sits inside the box, so the stroke centre is inset by
    // half its width.
    final rect = (Offset.zero & size).deflate(NeoSpinner.strokeWidth / 2);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = NeoSpinner.strokeWidth;
    // On a round box the transparent top border is the 90° quadrant centred
    // on 12 o'clock (-135° to -45°). Draw the other 270°, starting at -45°.
    canvas.drawArc(rect, -math.pi / 4, 1.5 * math.pi, false, paint);
  }

  @override
  bool shouldRepaint(_SpinnerPainter oldDelegate) => oldDelegate.color != color;
}
