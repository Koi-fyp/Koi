import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:google_fonts/google_fonts.dart';

import 'koi_colors.dart';

/// KOI typography.
///
/// Sources (repos/koi-backend/nextjs_app/):
/// - tailwind.config.ts fontFamily: display = 'Bricolage Grotesque',
///   body = 'DM Sans' (fallback system-ui, sans-serif)
/// - src/app/globals.css --font-display / --font-body, .neo-hero-text,
///   .neo-display
///
/// The web loads these from Google Fonts (globals.css @import). Mobile bundles
/// the same Google Fonts files in assets/google_fonts/ (web ranges: Bricolage
/// 200-800; DM Sans 300-700, italic 300-400) and main.dart disables runtime
/// fetching, so text renders correctly offline. Weights outside those ranges
/// are not bundled and must not be used.
abstract final class KoiText {
  static const String displayFamily = 'Bricolage Grotesque';
  static const String bodyFamily = 'DM Sans';

  /// When false, styles use the plain family names without asking
  /// google_fonts to fetch anything. Widget tests set this to false because
  /// google_fonts cannot fetch over the network inside `flutter test`.
  static bool useGoogleFonts = true;

  /// Display face (Bricolage Grotesque), used for headings and buttons.
  static TextStyle display({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    final base = TextStyle(
      fontSize: fontSize,
      fontWeight: _clamp(fontWeight, FontWeight.w200, FontWeight.w800),
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
    return useGoogleFonts
        ? GoogleFonts.bricolageGrotesque(textStyle: base)
        : base.copyWith(fontFamily: displayFamily);
  }

  /// Body face (DM Sans), the default for running text.
  static TextStyle body({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    final base = TextStyle(
      fontSize: fontSize,
      fontWeight: _clamp(fontWeight, FontWeight.w300, FontWeight.w700),
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
    return useGoogleFonts
        ? GoogleFonts.dmSans(textStyle: base)
        : base.copyWith(fontFamily: bodyFamily);
  }

  /// Clamps [w] to the bundled weight range. A weight outside it (e.g. web's
  /// font-weight 800/900 on DM Sans text) would make google_fonts look for a
  /// font file that isn't bundled, fail, and fall back to the system font.
  /// Browsers render such weights with the nearest loaded face, which is
  /// what clamping does.
  static FontWeight? _clamp(FontWeight? w, FontWeight min, FontWeight max) {
    if (w == null) return null;
    if (w.value < min.value) return min;
    if (w.value > max.value) return max;
    return w;
  }

  /// .neo-hero-text: font-size clamp(3rem, 8vw, 6rem); weight 800;
  /// line-height 0.9; letter-spacing -0.04em; color #000.
  /// [viewportWidth] stands in for the CSS viewport width (vw).
  static TextStyle hero(double viewportWidth) {
    final size = heroFontSize(viewportWidth);
    return display(
      fontSize: size,
      fontWeight: FontWeight.w800,
      height: 0.9,
      letterSpacing: -0.04 * size,
      color: KoiColors.neoBlack,
    );
  }

  /// clamp(3rem, 8vw, 6rem) with 1rem = 16px → clamp(48, 0.08 * width, 96).
  static double heroFontSize(double viewportWidth) =>
      math.min(96, math.max(48, 0.08 * viewportWidth));

  /// .neo-display: font-family display, weight 800.
  static TextStyle neoDisplay({double? fontSize, Color? color}) =>
      display(fontSize: fontSize, fontWeight: FontWeight.w800, color: color);
}
