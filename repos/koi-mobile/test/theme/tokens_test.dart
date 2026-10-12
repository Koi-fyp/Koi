import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/theme/koi_colors.dart';
import 'package:koi_mobile/theme/koi_motion.dart';
import 'package:koi_mobile/theme/koi_radii.dart';
import 'package:koi_mobile/theme/koi_shadows.dart';
import 'package:koi_mobile/theme/koi_text.dart';
import 'package:koi_mobile/theme/koi_theme.dart';

// Expected values are copied from repos/koi-backend/nextjs_app/
// tailwind.config.ts and src/app/globals.css.
void main() {
  test('neo colours match tailwind.config.ts', () {
    expect(KoiColors.neoBlue, const Color(0xFF2D63EB));
    expect(KoiColors.neoYellow, const Color(0xFFFFD100));
    expect(KoiColors.neoBlack, const Color(0xFF000000));
    expect(KoiColors.neoWhite, const Color(0xFFFFFFFF));
    expect(KoiColors.neoGray, const Color(0xFFF4F4F4));
    expect(KoiColors.neoMuted, const Color(0xFF6B7280));
    expect(KoiColors.neoCoral, const Color(0xFFFF6B6B));
    expect(KoiColors.neoMint, const Color(0xFF2DD36F));
    expect(KoiColors.neoPurple, const Color(0xFF845EC2));
    expect(KoiColors.neoOrange, const Color(0xFFFF9F43));
  });

  test('base and legacy colours match globals.css', () {
    expect(KoiColors.background, const Color(0xFFFFE5D9));
    expect(KoiColors.koiBrand, const Color(0xFFFF80AB));
    expect(KoiColors.koiAiBubble, const Color(0xFFF3E5F5));
    expect(KoiColors.koiDark, const Color(0xFF2D1B2E));
    expect(KoiColors.koiBorder, const Color(0xFFE8D5EC));
    expect(KoiColors.koiMuted, const Color(0xFF9E8C9E));
    expect(KoiColors.koiElevated, const Color(0xFFFFF0F5));
    expect(KoiColors.danger, const Color(0xFFFF4136));
    expect(KoiColors.focusRing.a, closeTo(0.2, 0.002));
  });

  test('radii use 1rem = 16px', () {
    expect(KoiRadii.neo, 20);
    expect(KoiRadii.koi, 40);
    expect(KoiRadii.xl2, 16);
    expect(KoiRadii.xl3, 24);
    expect(KoiRadii.xl4, 32);
    expect(KoiRadii.input, 12);
  });

  test('neo shadows are zero-blur black offsets', () {
    for (final (shadow, px) in [
      (KoiShadows.neoSm, 3.0),
      (KoiShadows.neoMd, 4.0),
      (KoiShadows.neoLg, 6.0),
      (KoiShadows.neoXl, 8.0),
    ]) {
      expect(shadow.single.offset, Offset(px, px));
      expect(shadow.single.blurRadius, 0);
      expect(shadow.single.spreadRadius, 0);
      expect(shadow.single.color, const Color(0xFF000000));
    }
    expect(KoiShadows.neoFocus.single.spreadRadius, 3);
    expect(KoiShadows.neoFocus.single.offset, Offset.zero);
    expect(KoiShadows.card.single.blurRadius, 24);
    expect(KoiShadows.card.single.offset, const Offset(0, 4));
    expect(KoiShadows.cardLg.single.blurRadius, 48);
    expect(KoiShadows.cardLg.single.offset, const Offset(0, 8));
    expect(KoiShadows.bubbly.single.offset, const Offset(0, 8));
    expect(KoiShadows.hardShadowCyan.single.color, const Color(0xFF06B6D4));
  });

  test('hero font size follows clamp(3rem, 8vw, 6rem)', () {
    expect(KoiText.heroFontSize(400), 48); // 32 → clamped up
    expect(KoiText.heroFontSize(800), 64);
    expect(KoiText.heroFontSize(1600), 96); // 128 → clamped down
    final s = KoiText.hero(800);
    expect(s.fontWeight, FontWeight.w800);
    expect(s.height, 0.9);
    expect(s.letterSpacing, closeTo(-2.56, 1e-9)); // -0.04em of 64
  });

  test('font families', () {
    expect(KoiText.display().fontFamily, 'Bricolage Grotesque');
    expect(KoiText.body().fontFamily, 'DM Sans');
  });

  test('animation specs match tailwind.config.ts', () {
    expect(KoiMotion.floatSlow.duration, const Duration(seconds: 5));
    expect(KoiMotion.floatMid.delay, const Duration(milliseconds: 700));
    expect(KoiMotion.floatFast.delay, const Duration(milliseconds: 1400));
    expect(KoiMotion.spinSlow.duration, const Duration(seconds: 8));
    expect(KoiMotion.fadeUp.duration, const Duration(milliseconds: 600));
    expect(KoiMotion.fadeUp.repeat, isFalse);
    expect(KoiMotion.slideRight.duration, const Duration(milliseconds: 500));
    expect(KoiMotion.pulseDot.duration, const Duration(seconds: 2));
  });

  test('keyframe tweens hit the web keyframe values', () {
    expect(KoiMotion.floatYTween.transform(0), 0);
    expect(KoiMotion.floatYTween.transform(0.5), closeTo(-12, 1e-9));
    expect(KoiMotion.floatYTween.transform(1), closeTo(0, 1e-9));
    expect(KoiMotion.pulseDotTween.transform(0), 1);
    expect(KoiMotion.pulseDotTween.transform(0.5), closeTo(0.4, 1e-9));
    expect(KoiMotion.pulseDotTween.transform(1), closeTo(1, 1e-9));
  });

  test('theme exposes tokens and the base background', () {
    final theme = KoiTheme.light();
    expect(theme.scaffoldBackgroundColor, KoiColors.background);
    expect(theme.colorScheme.primary, KoiColors.neoBlue);
    expect(theme.extension<KoiTokens>()!.accent, KoiColors.neoYellow);
  });
}
