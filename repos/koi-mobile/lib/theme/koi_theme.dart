import 'package:flutter/material.dart';

import 'koi_colors.dart';
import 'koi_text.dart';

/// Design tokens exposed through `Theme.of(context).extension<KoiTokens>()`.
/// Values come from koi_colors.dart (tailwind.config.ts / globals.css).
@immutable
class KoiTokens extends ThemeExtension<KoiTokens> {
  const KoiTokens({
    this.background = KoiColors.background,
    this.ink = KoiColors.neoBlack,
    this.surface = KoiColors.neoWhite,
    this.primary = KoiColors.neoBlue,
    this.accent = KoiColors.neoYellow,
    this.danger = KoiColors.danger,
    this.muted = KoiColors.neoMuted,
  });

  final Color background;
  final Color ink;
  final Color surface;
  final Color primary;
  final Color accent;
  final Color danger;
  final Color muted;

  @override
  KoiTokens copyWith({
    Color? background,
    Color? ink,
    Color? surface,
    Color? primary,
    Color? accent,
    Color? danger,
    Color? muted,
  }) =>
      KoiTokens(
        background: background ?? this.background,
        ink: ink ?? this.ink,
        surface: surface ?? this.surface,
        primary: primary ?? this.primary,
        accent: accent ?? this.accent,
        danger: danger ?? this.danger,
        muted: muted ?? this.muted,
      );

  @override
  KoiTokens lerp(KoiTokens? other, double t) {
    if (other == null) return this;
    return KoiTokens(
      background: Color.lerp(background, other.background, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
    );
  }
}

abstract final class KoiTheme {
  /// Light theme. Every colour is a KOI token; nothing is seed-generated.
  static ThemeData light() {
    // Body text uses DM Sans (globals.css `html, body { font-family:
    // var(--font-body) }`).
    final bodyFamily = KoiText.body().fontFamily;
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: KoiColors.background,
      fontFamily: bodyFamily,
      colorScheme: const ColorScheme.light(
        primary: KoiColors.neoBlue,
        onPrimary: KoiColors.neoWhite,
        secondary: KoiColors.neoYellow,
        onSecondary: KoiColors.neoBlack,
        error: KoiColors.danger,
        onError: KoiColors.neoWhite,
        surface: KoiColors.neoWhite,
        onSurface: KoiColors.neoBlack,
      ),
      extensions: const [KoiTokens()],
    );
  }
}
