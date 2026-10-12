import 'package:flutter/painting.dart';

/// KOI colour tokens, mirrored 1:1 from the web app.
///
/// Sources (all under repos/koi-backend/nextjs_app/):
/// - tailwind.config.ts  `theme.extend.colors.neo`
/// - src/app/globals.css `:root` custom properties and component classes
abstract final class KoiColors {
  // ── neo.* palette (tailwind.config.ts colors.neo; same values as the
  //    --neo-* vars in globals.css :root) ─────────────────────────────────
  static const Color neoBlue = Color(0xFF2D63EB);
  static const Color neoYellow = Color(0xFFFFD100);
  static const Color neoBlack = Color(0xFF000000);
  static const Color neoWhite = Color(0xFFFFFFFF);
  static const Color neoGray = Color(0xFFF4F4F4);
  static const Color neoMuted = Color(0xFF6B7280); // tailwind.config.ts only
  static const Color neoCoral = Color(0xFFFF6B6B);
  static const Color neoMint = Color(0xFF2DD36F);
  static const Color neoPurple = Color(0xFF845EC2);
  static const Color neoOrange = Color(0xFFFF9F43);

  /// Page base colour. globals.css `html, body { background-color: #ffe5d9 }`.
  /// The web also layers CDN grain/mesh/pattern images on top (.grain,
  /// .page-bg); mobile deliberately uses only this solid colour (playbook Q10).
  static const Color background = Color(0xFFFFE5D9);

  // ── Legacy chat tokens (globals.css :root "Legacy chat tokens") ──────────
  static const Color koiBrand = Color(0xFFFF80AB);
  static const Color koiAiBubble = Color(0xFFF3E5F5);
  static const Color koiDark = Color(0xFF2D1B2E);
  static const Color koiBorder = Color(0xFFE8D5EC);
  static const Color koiMuted = Color(0xFF9E8C9E);
  static const Color koiElevated = Color(0xFFFFF0F5);

  // ── Component colours that appear only as literals in globals.css ───────
  /// .neo-btn-danger background; also NeoInput.tsx error text colour.
  static const Color danger = Color(0xFFFF4136);

  /// .neo-input::placeholder colour (#aaa).
  static const Color inputPlaceholder = Color(0xFFAAAAAA);

  /// .hard-shadow-cyan, rgba(6,182,212,1).
  static const Color cyan = Color(0xFF06B6D4);

  /// .neo-input:focus ring and tailwind `neo-focus`, rgba(45,99,235,0.2).
  /// 0.2 * 255 = 51 = 0x33.
  static const Color focusRing = Color(0x332D63EB);
}
