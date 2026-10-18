import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/avatar/avatar_state.dart';
import 'package:koi_mobile/voice/voice_text.dart';

void main() {
  group('splitSentences', () {
    test('splits after . ! ? … ۔ ؟ and at line breaks', () {
      expect(
        splitSentences('Hi there. How are you?\nGood!  آپ کیسے ہیں؟ ٹھیک ہوں۔'),
        ['Hi there.', 'How are you?', 'Good!', 'آپ کیسے ہیں؟', 'ٹھیک ہوں۔'],
      );
    });

    test('no piece is longer than 450, cut at a comma, then a space', () {
      final commas = List.filled(60, 'word word,').join(' ');
      final spaces = List.filled(200, 'word').join(' ');
      final solid = 'x' * 1000;
      for (final text in [commas, spaces, solid]) {
        final parts = splitSentences(text);
        expect(parts.every((p) => p.length <= 450), isTrue);
        expect(parts.join().replaceAll(' ', ''), text.replaceAll(' ', ''));
      }
      expect(splitSentences(commas).first, endsWith(','));
      expect(splitSentences(spaces).first, endsWith('word'));
      expect(splitSentences(solid).map((p) => p.length), [450, 450, 100]);
    });

    test('a custom limit is respected too', () {
      expect(splitSentences('aaa bbb ccc', max: 5), ['aaa', 'bbb', 'ccc']);
    });
  });

  group('planSpeech voice and language', () {
    SpeakPlan plan(String text, CompanionAvatar c, [String? lang]) =>
        planSpeech(text, companion: c, userLanguage: lang) as SpeakPlan;

    test('Latin → *_en / en, Urdu script → *_ur / ur', () {
      final en = plan('Hello there.', CompanionAvatar.raza);
      expect(en.parts.single.voiceId, 'raza_en');
      expect(en.parts.single.language, 'en');
      expect(en.deviceOnly, isFalse);

      final ur = plan('آپ کیسے ہیں؟', CompanionAvatar.aisha);
      expect(ur.parts.single.voiceId, 'aisha_ur');
      expect(ur.parts.single.language, 'ur');
    });

    test('Aisha → aisha_*, Raza and Koi fox → raza_*', () {
      expect(
        plan('Hi.', CompanionAvatar.aisha).parts.single.voiceId,
        'aisha_en',
      );
      expect(plan('Hi.', CompanionAvatar.raza).parts.single.voiceId, 'raza_en');
      expect(plan('Hi.', CompanionAvatar.koi).parts.single.voiceId, 'raza_en');
    });

    test('a sentence with both scripts → device voice for the whole reply', () {
      final p = plan('First sentence. Hello آپ کیسے ہیں', CompanionAvatar.raza);
      expect(p.deviceOnly, isTrue);
    });

    test('separate Urdu and Latin sentences are not mixed', () {
      final p = plan('Hello. آپ کیسے ہیں؟ Bye.', CompanionAvatar.aisha);
      expect(p.deviceOnly, isFalse);
      expect(p.parts.map((x) => x.voiceId), [
        'aisha_en',
        'aisha_ur',
        'aisha_en',
      ]);
    });

    test('Roman Urdu for an Urdu user stays text only', () {
      expect(
        planSpeech(
          'Aap kaise hain?',
          companion: CompanionAvatar.raza,
          userLanguage: 'ur',
        ),
        isA<SilentPlan>(),
      );
      // Urdu setting with Urdu script is spoken.
      expect(
        plan('آپ کیسے ہیں؟', CompanionAvatar.raza, 'ur').parts.single.voiceId,
        'raza_ur',
      );
      // English setting: Latin is English.
      expect(
        plan(
          'Aap kaise hain?',
          CompanionAvatar.raza,
          'en',
        ).parts.single.language,
        'en',
      );
    });

    test('nothing to say → silent', () {
      expect(
        planSpeech('  123 !!! ', companion: CompanionAvatar.raza),
        isA<SilentPlan>(),
      );
    });

    test('first part alone, later same-language sentences joined ≤450', () {
      final text = List.generate(
        12,
        (i) => 'Sentence number $i is here.',
      ).join(' ');
      final p = plan(text, CompanionAvatar.raza);
      expect(p.parts.first.text, 'Sentence number 0 is here.');
      expect(p.parts.length, lessThan(12));
      expect(p.parts.every((x) => x.text.length <= 450), isTrue);
      expect(p.parts.map((x) => x.text).join(' '), text);
    });
  });
}
