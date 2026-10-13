import 'package:flutter/widgets.dart';

/// Paints a zero-blur stadium (pill) shadow only where it sticks out from
/// under the widget.
///
/// CSS `box-shadow` (outer) is never drawn beneath the element's own box, so
/// a button with `background: transparent` (globals.css `.neo-btn-ghost`)
/// shows the page through its fill and the shadow only outside it. Flutter's
/// BoxShadow paints the whole shape under the widget, which turns a
/// transparent button into a solid block of the shadow colour. Use this for
/// any transparent widget with a hard shadow.
class OuterStadiumShadowPainter extends CustomPainter {
  const OuterStadiumShadowPainter({required this.color, required this.offset});

  final Color color;
  final Offset offset;

  @override
  void paint(Canvas canvas, Size size) {
    if (offset == Offset.zero) return;
    final box = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRRect(box.shift(offset)),
      Path()..addRRect(box),
    );
    canvas.drawPath(outside, Paint()..color = color);
  }

  @override
  bool shouldRepaint(OuterStadiumShadowPainter old) =>
      old.color != color || old.offset != offset;
}
