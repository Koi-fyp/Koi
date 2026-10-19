import 'package:flutter/widgets.dart';

import 'svg_path.dart';

/// The nav icons, drawn from the exact SVG data in
/// repos/koi-backend/nextjs_app/src/components/layout/BottomNav.tsx
/// (ChatIcon, ProgressIcon, SettingsIcon) and ModeSelector.tsx (chevron).
/// All use viewBox="0 0 24 24" and stroke="currentColor"; the BottomNav icons
/// use round caps and joins.
enum KoiNavGlyph { chat, progress, settings, chevronDown, care }

class KoiNavIcon extends StatelessWidget {
  const KoiNavIcon(
    this.glyph, {
    super.key,
    required this.color,
    this.active = false,
    this.size = 17, // width="17" height="17"
  });

  final KoiNavGlyph glyph;

  /// CSS `currentColor`.
  final Color color;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _NavIconPainter(glyph, color, active)),
  );
}

// BottomNav.tsx ChatIcon <path d>
const String _chatPath =
    'M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z';
// BottomNav.tsx ProgressIcon <polyline points>
const String _progressPoints = '22 12 18 12 15 21 9 3 6 12 2 12';
// BottomNav.tsx SettingsIcon <circle cx=12 cy=12 r=3> + <path d>
const String _settingsPath =
    'M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z';
// MOB-1 Care tab (mobile-only, no web source): the Feather "heart" path,
// the same icon set, viewBox and stroke style as the BottomNav icons.
const String _carePath =
    'M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 '
    '7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z';
// ModeSelector.tsx chevron <polyline points>
const String _chevronPoints = '6 9 12 15 18 9';

final Path chatIconPath = parseSvgPath(_chatPath);
final Path progressIconPath = parseSvgPolyline(_progressPoints);
final Path settingsIconPath = parseSvgPath(_settingsPath);
final Path chevronDownPath = parseSvgPolyline(_chevronPoints);
final Path careIconPath = parseSvgPath(_carePath);

class _NavIconPainter extends CustomPainter {
  _NavIconPainter(this.glyph, this.color, this.active);

  final KoiNavGlyph glyph;
  final Color color;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24); // viewBox 0 0 24 24
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      // BottomNav icons: strokeWidth={active ? 2.5 : 2};
      // ModeSelector chevron: strokeWidth="2.5".
      ..strokeWidth = glyph == KoiNavGlyph.chevronDown
          ? 2.5
          : (active ? 2.5 : 2);

    switch (glyph) {
      case KoiNavGlyph.chat:
        if (active) {
          // fill={active ? 'currentColor' : 'none'} fillOpacity={0.25}
          canvas.drawPath(
            chatIconPath,
            Paint()..color = color.withValues(alpha: color.a * 0.25),
          );
        }
        canvas.drawPath(chatIconPath, stroke);
      case KoiNavGlyph.progress:
        canvas.drawPath(progressIconPath, stroke);
      case KoiNavGlyph.care:
        if (active) {
          // Same active fill as the chat icon.
          canvas.drawPath(
            careIconPath,
            Paint()..color = color.withValues(alpha: color.a * 0.25),
          );
        }
        canvas.drawPath(careIconPath, stroke);
      case KoiNavGlyph.settings:
        // The <circle> has no strokeLinecap/Join; irrelevant for a circle.
        canvas.drawCircle(const Offset(12, 12), 3, stroke);
        canvas.drawPath(settingsIconPath, stroke);
      case KoiNavGlyph.chevronDown:
        // The chevron <svg> sets no linecap/linejoin: SVG defaults butt/miter.
        canvas.drawPath(
          chevronDownPath,
          stroke
            ..strokeCap = StrokeCap.butt
            ..strokeJoin = StrokeJoin.miter,
        );
    }
  }

  @override
  bool shouldRepaint(_NavIconPainter old) =>
      old.glyph != glyph || old.color != color || old.active != active;
}
