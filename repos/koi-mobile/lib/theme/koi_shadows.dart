import 'package:flutter/painting.dart';

import 'koi_colors.dart';

/// KOI box shadows.
///
/// Source: repos/koi-backend/nextjs_app/tailwind.config.ts
/// `theme.extend.boxShadow`, plus helpers from src/app/globals.css.
///
/// CSS `box-shadow: x y blur spread color` maps to
/// BoxShadow(offset: Offset(x, y), blurRadius: blur, spreadRadius: spread).
/// Note: CSS blur and Flutter blurRadius are both "blur radius", but browsers
/// and Skia/Impeller rasterise soft shadows slightly differently, so the soft
/// shadows (bubbly, card, cardLg) are close but not pixel-identical. The
/// neo-* shadows have zero blur and match exactly.
abstract final class KoiShadows {
  /// Hard, zero-blur black offset shadow of [px] in x and y.
  static List<BoxShadow> hard(double px, [Color color = KoiColors.neoBlack]) =>
      [BoxShadow(color: color, offset: Offset(px, px))];

  // tailwind.config.ts boxShadow
  static final List<BoxShadow> neoSm = hard(3); // 'neo-sm' 3px 3px 0 0 #000
  static final List<BoxShadow> neoMd = hard(4); // 'neo-md' 4px 4px 0 0 #000
  static final List<BoxShadow> neoLg = hard(6); // 'neo-lg' 6px 6px 0 0 #000
  static final List<BoxShadow> neoXl = hard(8); // 'neo-xl' 8px 8px 0 0 #000

  /// 'neo-focus': 0 0 0 3px rgba(45,99,235,0.2)
  static const List<BoxShadow> neoFocus = [
    BoxShadow(color: KoiColors.focusRing, spreadRadius: 3),
  ];

  /// bubbly: 0 8px 0px 0px rgba(0,0,0,0.05)   (0.05*255 ≈ 13 = 0x0D)
  static const List<BoxShadow> bubbly = [
    BoxShadow(color: Color(0x0D000000), offset: Offset(0, 8)),
  ];

  /// card: 0 4px 24px 0 rgba(0,0,0,0.08)   (0.08*255 ≈ 20 = 0x14)
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x14000000), offset: Offset(0, 4), blurRadius: 24),
  ];

  /// card-lg: 0 8px 48px 0 rgba(0,0,0,0.12)   (0.12*255 ≈ 31 = 0x1F)
  static const List<BoxShadow> cardLg = [
    BoxShadow(color: Color(0x1F000000), offset: Offset(0, 8), blurRadius: 48),
  ];

  // globals.css helpers
  /// .hard-shadow: 5px 5px 0 0 rgba(0,0,0,1)
  static final List<BoxShadow> hardShadow = hard(5);

  /// .hard-shadow-cyan: 5px 5px 0 0 rgba(6,182,212,1)
  static final List<BoxShadow> hardShadowCyan = hard(5, KoiColors.cyan);
}
