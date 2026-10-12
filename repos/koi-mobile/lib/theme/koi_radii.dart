import 'package:flutter/painting.dart';

/// KOI corner radii.
///
/// Source: repos/koi-backend/nextjs_app/tailwind.config.ts
/// `theme.extend.borderRadius`, plus literals from src/app/globals.css.
///
/// ASSUMPTION: 1rem = 16 logical pixels (the browser default root font size;
/// globals.css never changes the html font-size).
abstract final class KoiRadii {
  static const double rem = 16;

  static const double neo = 1.25 * rem; // 20  (borderRadius.neo)
  static const double koi = 2.5 * rem; //  40  (borderRadius.koi)
  static const double xl2 = 1 * rem; //    16  (borderRadius.xl2)
  static const double xl3 = 1.5 * rem; //  24  (borderRadius.xl3)
  static const double xl4 = 2 * rem; //    32  (borderRadius.xl4)

  /// .neo-input border-radius: 0.75rem.
  static const double input = 0.75 * rem; // 12

  /// `border-radius: 9999px` (.neo-btn-*). Rendered as a stadium shape.
  static const double pill = 9999;

  static const BorderRadius neoAll = BorderRadius.all(Radius.circular(neo));
  static const BorderRadius koiAll = BorderRadius.all(Radius.circular(koi));
  static const BorderRadius inputAll = BorderRadius.all(Radius.circular(input));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}
