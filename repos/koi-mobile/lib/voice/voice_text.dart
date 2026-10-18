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

/// What to do with one completed reply.
sealed class VoicePlan {
  const VoicePlan();
}

/// Text only: nothing to speak, or Roman Urdu for an Urdu user (backend
/// asked to keep Roman Urdu text-only, 2026-10-18).
class SilentPlan extends VoicePlan {
  const SilentPlan();
}

class SpeakPlan extends VoicePlan {
  const SpeakPlan(this.parts, {required this.deviceOnly});

  /// Each at most [maxSpeechChars] characters.
  final List<SpeechPart> parts;

  /// A sentence mixes Urdu and Latin letters: the server answers 422 for
  /// that, so the whole reply uses the device voice.
  final bool deviceOnly;
}

final RegExp _urdu = RegExp(r'[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]');
final RegExp _latin = RegExp(r'[A-Za-zÀ-ɏ]');

bool hasUrduLetters(String s) => _urdu.hasMatch(s);
bool hasLatinLetters(String s) => _latin.hasMatch(s);

/// Raza for Raza and Koi's fox (decided 2026-10-18), Aisha for Aisha.
String voicePrefix(CompanionAvatar companion) =>
    companion == CompanionAvatar.aisha ? 'aisha' : 'raza';

/// Sentences of [text], each at most [max] characters: split after
/// . ! ? … ۔ ؟ (followed by a space) and at line breaks; a longer sentence
/// is cut at its last comma / semicolon, else its last space, else at [max].
List<String> splitSentences(String text, {int max = maxSpeechChars}) {
  final out = <String>[];
  final pieces = text.split(RegExp(r'(?<=[.!?…۔؟])\s+|\s*\n\s*'));
  for (var piece in pieces) {
    piece = piece.trim();
    while (piece.length > max) {
      final head = piece.substring(0, max);
      var cut = head.lastIndexOf(RegExp(r'[,;،؛]\s'));
      if (cut > 0) {
        cut += 1;
      } else {
        cut = head.lastIndexOf(' ');
        if (cut <= 0) cut = max;
      }
      out.add(piece.substring(0, cut).trim());
      piece = piece.substring(cut).trim();
    }
    if (piece.isNotEmpty) out.add(piece);
  }
  return out;
}

/// What to say for a completed reply:
/// - no letters at all → [SilentPlan];
/// - Language setting Urdu ([userLanguage] 'ur') and no Urdu-script letter
///   (Roman Urdu) → [SilentPlan];
/// - a sentence with both scripts → device voice for the whole reply;
/// - otherwise Urdu-script sentences → `*_ur`/'ur', Latin → `*_en`/'en'.
///
/// The first sentence is its own part so it can play as soon as it
/// arrives; later sentences in the same language are joined up to
/// [maxSpeechChars], keeping requests within the 10/min limit.
VoicePlan planSpeech(
  String reply, {
  required CompanionAvatar companion,
  String? userLanguage,
}) {
  final sentences = splitSentences(reply);
  final anyUrdu = sentences.any(hasUrduLetters);
  final anyLatin = sentences.any(hasLatinLetters);
  if (!anyUrdu && !anyLatin) return const SilentPlan();
  if (userLanguage == 'ur' && !anyUrdu) return const SilentPlan();

  final prefix = voicePrefix(companion);
  var mixed = false;
  String? previous;
  final parts = <SpeechPart>[];
  for (final s in sentences) {
    final urdu = _urdu.allMatches(s).length;
    final latin = _latin.allMatches(s).length;
    if (urdu > 0 && latin > 0) mixed = true;
    // No letters (numbers, emoji): same language as the sentence before.
    final language = urdu == 0 && latin == 0
        ? previous ?? (anyUrdu && !anyLatin ? 'ur' : 'en')
        : urdu >= latin
        ? 'ur'
        : 'en';
    previous = language;
    // Never joined onto the first part.
    final last = parts.length > 1 ? parts.last : null;
    if (last != null &&
        last.language == language &&
        last.text.length + 1 + s.length <= maxSpeechChars) {
      parts[parts.length - 1] = SpeechPart(
        '${last.text} $s',
        voiceId: last.voiceId,
        language: language,
      );
    } else {
      parts.add(
        SpeechPart(s, voiceId: '${prefix}_$language', language: language),
      );
    }
  }
  return SpeakPlan(List.unmodifiable(parts), deviceOnly: mixed);
}
