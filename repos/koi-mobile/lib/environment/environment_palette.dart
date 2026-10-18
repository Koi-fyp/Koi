import 'package:flutter/animation.dart';

import '../avatar/avatar_state.dart';
import '../theme/koi_colors.dart';

/// What the background shows (SDS Module 6, Prompt 27): the companion's
/// latest emotion, or [calm] during breathing / the crisis flow.
enum EnvironmentMood {
  neutral,
  joy,
  angry,
  sorrow,
  fun,
  calm;

  /// The chat stream's companion_state emotion (AvatarEmotion, the backend's
  /// `neutral | joy | angry | sorrow | fun`). null → neutral.
  static EnvironmentMood fromEmotion(AvatarEmotion? emotion) =>
      switch (emotion) {
        AvatarEmotion.joy => joy,
        AvatarEmotion.angry => angry,
        AvatarEmotion.sorrow => sorrow,
        AvatarEmotion.fun => fun,
        AvatarEmotion.neutral || null => neutral,
      };
}

/// The soft background tints. The web app has no environment tint, so each
/// one is the page colour ([KoiColors.background], #FFE5D9) with a small
/// share of an existing design-system token blended in (approved
/// 2026-10-18). Never saturated; text that sits on the background must stay
/// at least 4.5:1 against every tint (test/environment).
abstract final class EnvironmentPalette {
  /// Share of the token on the call screen (the avatar card covers most of
  /// it, so the tint shows around it). Tune here.
  static const double callStrength = 0.12;

  /// Share of the token on the Chat tab (message area + top nav). Tune here.
  static const double chatStrength = 0.06;

  /// Colour change duration; instant when the system removes animations.
  static const Duration transition = Duration(milliseconds: 1800);
  static const Curve curve = Curves.easeInOut;

  /// The token blended in for [mood]; null = the plain page colour.
  /// angry is a soft lavender and calm a soft teal-grey: never red, orange
  /// or anything alarming.
  static Color? token(EnvironmentMood mood) => switch (mood) {
    EnvironmentMood.neutral => null,
    EnvironmentMood.joy => KoiColors.neoYellow,
    EnvironmentMood.fun => KoiColors.neoMint,
    EnvironmentMood.sorrow => KoiColors.neoBlue,
    EnvironmentMood.angry => KoiColors.neoPurple,
    EnvironmentMood.calm => KoiColors.cyan,
  };

  /// The background for [mood] at [strength] (0 = page colour).
  static Color colorFor(EnvironmentMood mood, double strength) {
    final tint = token(mood);
    if (tint == null) return KoiColors.background;
    return Color.lerp(KoiColors.background, tint, strength)!;
  }
}
