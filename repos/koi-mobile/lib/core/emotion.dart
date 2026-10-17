import 'package:flutter/foundation.dart';

/// The ONE place mobile defines emotion labels (Q6, decided 2026-10-13).
///
/// Mirrors the web code's deployed union, `Emotion` in
/// repos/koi-backend/nextjs_app/src/lib/conversation/conversationService.ts
/// (and lib/db.ts): 'happy' | 'sad' | 'anxious' | 'calm' | 'neutral'.
/// The docs use a different set (neutral, joy, angry, sorrow, fun); change it
/// here only, once the taxonomy is locked.
enum Emotion {
  happy,
  sad,
  anxious,
  calm,
  neutral;

  /// The wire/storage value, identical to web.
  String get wire => name;

  /// Parses a stored value; anything unknown is 'neutral' (web toChat():
  /// `(r.emotion as Emotion) ?? 'neutral'`).
  static Emotion fromWire(Object? raw) =>
      values.firstWhere((e) => e.name == raw, orElse: () => Emotion.neutral);
}

/// The label stored with an AI message for the backend's companion_state
/// emotion (`neutral | joy | angry | sorrow | fun`). Mirrors storedEmotion()
/// in feat/web-v11-wiring conversationService.ts: joy → happy, sorrow → sad,
/// fun → calm, anything else → neutral. Storage format is unchanged.
Emotion storedEmotion(String companionEmotion) => switch (companionEmotion) {
  'joy' => Emotion.happy,
  'sorrow' => Emotion.sad,
  'fun' => Emotion.calm,
  _ => Emotion.neutral,
};

/// Mirrors normalizeEmotion() in conversationService.ts: a deliberate,
/// visible shim, NOT a canonical mapping. Known labels pass through; any other
/// string is logged and becomes 'neutral'; non-strings become 'neutral'
/// silently.
Emotion normalizeEmotion(Object? raw) {
  if (raw is String) {
    for (final e in Emotion.values) {
      if (e.name == raw) return e;
    }
    debugPrint('[KOI] Unmapped emotion from backend, using neutral: $raw');
  }
  return Emotion.neutral;
}
