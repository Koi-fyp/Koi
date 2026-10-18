import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/avatar/avatar_state.dart';
import 'package:koi_mobile/voice/voice_text.dart';

void main() {
  group('ATC-M3-01 splitSentences', () {
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

  group('ATC-M3-02 planSpeech voice and language', () {
    SpeakPlan plan(String text, CompanionAvatar c, [String? lang]) =>
        planSpeech(text, companion: c, userLanguage: lang) as SpeakPlan;
    SilentReason? silent(String text, CompanionAvatar c, [String? lang]) =>
        switch (planSpeech(text, companion: c, userLanguage: lang)) {
          SilentPlan(:final reason) => reason,
          SpeakPlan() => null,
        };

    test('Latin → *_en / en, Urdu script → *_ur / ur', () {
      final en = plan('Hello there.', CompanionAvatar.raza);
      expect(en.parts.single.voiceId, 'raza_en');
      expect(en.parts.single.language, 'en');

      final ur = plan('آپ کیسے ہیں؟', CompanionAvatar.aisha);
      expect(ur.parts.single.voiceId, 'aisha_ur');
      expect(ur.parts.single.language, 'ur');
    });

    // Changed in Prompt 29: the fox no longer speaks with Raza's voice.
    test('Aisha → aisha_*, Raza → raza_*, Koi fox → silent', () {
      expect(
        plan('Hi.', CompanionAvatar.aisha).parts.single.voiceId,
        'aisha_en',
      );
      expect(plan('Hi.', CompanionAvatar.raza).parts.single.voiceId, 'raza_en');
      expect(silent('Hi.', CompanionAvatar.koi), SilentReason.noVoice);
    });

    // Changed in Prompt 29: was the device voice for the whole reply.
    test('a sentence with both scripts → the whole reply is silent', () {
      expect(
        silent('First sentence. Hello آپ کیسے ہیں', CompanionAvatar.raza),
        SilentReason.mixed,
      );
    });

    // Changed in Prompt 29: was en / ur / en voices per sentence.
    test('separate Urdu and Latin sentences → mixed reply, silent', () {
      expect(
        silent('Hello. آپ کیسے ہیں؟ Bye.', CompanionAvatar.aisha),
        SilentReason.mixed,
      );
    });

    test('Roman Urdu for an Urdu user stays text only', () {
      expect(
        silent('Aap kaise hain?', CompanionAvatar.raza, 'ur'),
        SilentReason.urduSettingLatin,
      );
      // Urdu setting with Urdu script is spoken.
      expect(
        plan('آپ کیسے ہیں؟', CompanionAvatar.raza, 'ur').parts.single.voiceId,
        'raza_ur',
      );
      // Changed in Prompt 29: English setting no longer reads Roman Urdu
      // with the English voice.
      expect(
        silent('Aap kaise hain?', CompanionAvatar.raza, 'en'),
        SilentReason.romanUrdu,
      );
    });

    test('nothing to say → silent', () {
      expect(silent('  123 !!! ', CompanionAvatar.raza), SilentReason.empty);
    });
  });

  group('ATC-M3-38 Roman Urdu: word list and the 2-different-words rule', () {
    test('the approved list, including the ten words named in Prompt 29', () {
      expect(
        romanUrduWords,
        containsAll(<String>[
          'hai',
          'nahi',
          'main',
          'mein',
          'aap',
          'tum',
          'kya',
          'ko',
          'ke',
          'ka',
        ]),
      );
      expect(romanUrduWords, hasLength(49));
    });

    test('2 different listed words → Roman Urdu; repeats count once', () {
      expect(isRomanUrdu('Tum theek ho?'), isTrue);
      expect(isRomanUrdu('Mujhe nahi pata, yaar.'), isTrue);
      expect(isRomanUrdu('Ho ho ho, merry Christmas!'), isFalse);
      expect(isRomanUrdu('The main thing is to rest.'), isFalse);
      expect(isRomanUrdu('KYA HAI'), isTrue, reason: 'case-insensitive');
      expect(isRomanUrdu('Kaam-kaaj'), isFalse, reason: 'one word, twice');
    });

    test('an English reply with one listed word is still spoken', () {
      final p = planSpeech(
        'Take a breath and focus on the main idea.',
        companion: CompanionAvatar.raza,
      ) as SpeakPlan;
      expect(p.parts.single.voiceId, 'raza_en');
    });
  });

  group('ATC-M3-39 chunk sizes: first ~60, later 140–220 at sentences', () {
    String sentence(int i) => 'This is sentence number $i of the reply.';

    test('a short first sentence is the first chunk on its own', () {
      final text = List.generate(10, sentence).join(' ');
      final chunks = chunkReply(text);
      expect(chunks.first, sentence(0));
      expect(chunks.join(' '), text);
      final later = chunks.sublist(1);
      for (final c in later.sublist(0, later.length - 1)) {
        expect(c.length, inInclusiveRange(ChunkSize.min, ChunkSize.max));
      }
      expect(later.last.length, lessThanOrEqualTo(ChunkSize.max));
      // Whole sentences only.
      for (final c in later) {
        expect(c, endsWith('reply.'));
      }
    });

    test(
      'a long first sentence is cut at or before 60 (comma, else space)',
      () {
        const first =
            'When everything feels heavy at once, it can help to slow down and '
            'name just one small thing you can do next.';
        final chunks = chunkReply('$first Then we can go on.');
        expect(chunks.first, 'When everything feels heavy at once,');
        expect(chunks.first.length, lessThanOrEqualTo(ChunkSize.first));
        expect(chunks.join(' '), '$first Then we can go on.');

        final noComma = List.filled(30, 'word').join(' ');
        final c2 = chunkReply(noComma);
        expect(c2.first.length, lessThanOrEqualTo(ChunkSize.first));
        expect(c2.first, endsWith('word'));
      },
    );

    test('a first sentence of up to 80 characters stays whole', () {
      final s80 = '${'a' * 76} ok.';
      expect(s80.length, 80);
      expect(chunkReply('$s80 Next.').first, s80);
    });

    test('no chunk is longer than 220; a long sentence is cut', () {
      final long = List.filled(120, 'calm').join(' ');
      final chunks = chunkReply('Hi. $long.');
      expect(chunks.first, 'Hi.');
      expect(chunks.every((c) => c.length <= ChunkSize.max), isTrue);
      expect(chunks.join(' '), 'Hi. $long.');
    });

    test('planSpeech uses the same chunks, one voice for all', () {
      final text = List.generate(8, sentence).join(' ');
      final p = planSpeech(text, companion: CompanionAvatar.aisha) as SpeakPlan;
      expect(p.parts.map((x) => x.text), chunkReply(text));
      expect(p.parts.map((x) => x.voiceId).toSet(), {'aisha_en'});
    });
  });
}
