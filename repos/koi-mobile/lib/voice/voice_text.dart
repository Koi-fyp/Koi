import '../avatar/avatar_state.dart' show CompanionAvatar;
import 'speech_api.dart' show maxSpeechChars;

/// One piece of a reply to speak, in one voice and language.
class SpeechPart {
  const SpeechPart(this.text, {required this.voiceId, required this.language});

  final String text;

  /// raza_en, raza_ur, aisha_en or aisha_ur.
  final String voiceId;

  /// 'en' or 'ur'.
  final String language;

  @override
  String toString() => 'SpeechPart($voiceId, $language, ${text.length})';
}

/// Why a reply stays text only.
enum SilentReason {
  /// No letters at all.
  empty,

  /// Koi's fox (no voice, Ahmad 2026-10-18).
  noVoice,

  /// Urdu-script and Latin letters in the same reply (Prompt 29: silent,
  /// as web replyVoicePolicy.ts planReplyVoice; was the device voice).
  mixed,

  /// Latin-only reply with 2+ different [romanUrduWords].
  romanUrdu,

  /// Language setting Urdu and no Urdu-script letter (Prompt 25).
  urduSettingLatin,
}

/// What to do with one completed reply.
sealed class VoicePlan {
  const VoicePlan();
}

/// Text only.
class SilentPlan extends VoicePlan {
  const SilentPlan(this.reason);
  final SilentReason reason;
}

/// The whole reply in one voice, in [parts] (see [chunkReply]).
class SpeakPlan extends VoicePlan {
  const SpeakPlan(this.parts);
  final List<SpeechPart> parts;
}

// Letters only (web chunkReply.ts ARABIC_LETTER / LATIN_LETTER): Arabic-
// script punctuation (، ؟ ۔) and digits are neutral.
final RegExp _urdu = RegExp(
  '[ؠ-يٮ-ۓەۮۯۺ-ۿ'
  'ݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-ﻼ]',
);
final RegExp _latin = RegExp('[A-Za-zÀ-ÖØ-öø-ɏḀ-ỿ]');

bool hasUrduLetters(String s) => _urdu.hasMatch(s);
bool hasLatinLetters(String s) => _latin.hasMatch(s);

/// Common Roman Urdu words (approved 2026-10-18): web replyVoicePolicy.ts
/// ROMAN_URDU_WORDS plus the second row.
const Set<String> romanUrduWords = {
  'hai', 'nahi', 'main', 'mein', 'aap', 'tum', 'kya', 'ko', 'ke', 'ka', //
  'ki', 'ho', 'hoon', 'mujhe', 'kaam', 'yaar', 'aur', 'se', 'ne', 'par', //
  'hain', 'nahin', 'bhi', 'kuch', 'kyun', 'kaise', 'yeh', 'woh', 'mera', //
  'meri', 'tera', 'teri', 'apna', 'apni', 'raha', 'rahi', 'rahe', 'theek', //
  'acha', 'achha', 'bahut', 'bohat', 'lekin', 'phir', 'abhi', 'hota', //
  'hoti', 'karo', 'karna',
};

/// Roman Urdu: at least 2 *different* listed words ("ho ho ho" is one).
/// One is ignored: several ("main", "par", "ho", "se") are also English.
bool isRomanUrdu(String text) =>
    RegExp(r'[a-z]+')
        .allMatches(text.toLowerCase())
        .map((m) => m[0]!)
        .where(romanUrduWords.contains)
        .toSet()
        .length >=
    2;

/// Aisha → aisha, Raza → raza; Koi's fox has no voice.
String? voicePrefix(CompanionAvatar companion) => switch (companion) {
  CompanionAvatar.aisha => 'aisha',
  CompanionAvatar.raza => 'raza',
  CompanionAvatar.koi => null,
};

/// Sentences of [text], each at most [max] characters: split after
/// . ! ? … ۔ ؟ (followed by a space) and at line breaks; a longer sentence
/// is cut at its last comma / semicolon, else its last space, else at [max].
List<String> splitSentences(String text, {int max = maxSpeechChars}) {
  final out = <String>[];
  final pieces = text.split(RegExp(r'(?<=[.!?…۔؟])\s+|\s*\n\s*'));
  for (var piece in pieces) {
    piece = piece.trim();
    while (piece.length > max) {
      final (head, rest) = _cut(piece, max);
      out.add(head);
      piece = rest;
    }
    if (piece.isNotEmpty) out.add(piece);
  }
  return out;
}

/// [text] cut at or before [max]: after its last comma / semicolon, else
/// at its last space, else at [max].
(String, String) _cut(String text, int max) {
  final head = text.substring(0, max);
  var cut = head.lastIndexOf(RegExp(r'[,;،؛]\s'));
  if (cut > 0) {
    cut += 1;
  } else {
    cut = head.lastIndexOf(' ');
    if (cut <= 0) cut = max;
  }
  return (text.substring(0, cut).trim(), text.substring(cut).trim());
}

/// Chunk sizes (Ahmad, 2026-10-18): a short first chunk so audio starts
/// quickly, then 140–220 characters at sentence boundaries.
abstract final class ChunkSize {
  /// The first chunk is the first sentence when it is at most [firstWhole]
  /// characters, else that sentence cut at or before [first].
  static const int first = 60;
  static const int firstWhole = 80;

  /// Later chunks: whole sentences joined while the chunk is under [min]
  /// and the next sentence still fits in [max]; a longer sentence is cut
  /// at or before [max].
  static const int min = 140;
  static const int max = 220;
}

/// The chunks of a single-script reply, in order (see [ChunkSize]).
List<String> chunkReply(String text) {
  final sentences = splitSentences(text, max: ChunkSize.max);
  if (sentences.isEmpty) return const [];
  final out = <String>[];
  var rest = sentences;
  final first = sentences.first;
  if (first.length <= ChunkSize.firstWhole) {
    out.add(first);
    rest = sentences.sublist(1);
  } else {
    final (head, tail) = _cut(first, ChunkSize.first);
    out.add(head);
    rest = [if (tail.isNotEmpty) tail, ...sentences.sublist(1)];
  }
  String? current;
  for (final s in rest) {
    final c = current;
    if (c != null &&
        c.length < ChunkSize.min &&
        c.length + 1 + s.length <= ChunkSize.max) {
      current = '$c $s';
    } else {
      if (c != null) out.add(c);
      current = s;
    }
  }
  if (current != null) out.add(current);
  return out;
}

/// What to say for a completed reply, decided for the whole reply:
/// - Koi's fox → [SilentReason.noVoice];
/// - no letters → [SilentReason.empty];
/// - Urdu-script and Latin letters → [SilentReason.mixed];
/// - Latin only: Language setting Urdu ([userLanguage] 'ur') →
///   [SilentReason.urduSettingLatin]; Roman Urdu ([isRomanUrdu]) →
///   [SilentReason.romanUrdu];
/// - otherwise one voice for every chunk: `*_ur`/'ur' for Urdu script,
///   `*_en`/'en' for Latin.
///
/// Exercise and crisis turns are decided by the call screen.
VoicePlan planSpeech(
  String reply, {
  required CompanionAvatar companion,
  String? userLanguage,
}) {
  final prefix = voicePrefix(companion);
  if (prefix == null) return const SilentPlan(SilentReason.noVoice);
  final urdu = hasUrduLetters(reply);
  final latin = hasLatinLetters(reply);
  if (!urdu && !latin) return const SilentPlan(SilentReason.empty);
  if (urdu && latin) return const SilentPlan(SilentReason.mixed);
  if (latin) {
    if (userLanguage == 'ur') {
      return const SilentPlan(SilentReason.urduSettingLatin);
    }
    if (isRomanUrdu(reply)) return const SilentPlan(SilentReason.romanUrdu);
  }
  final language = urdu ? 'ur' : 'en';
  return SpeakPlan(
    List.unmodifiable([
      for (final chunk in chunkReply(reply))
        SpeechPart(chunk, voiceId: '${prefix}_$language', language: language),
    ]),
  );
}
