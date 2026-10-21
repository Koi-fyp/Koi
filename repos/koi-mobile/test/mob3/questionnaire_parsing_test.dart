import 'dart:io';

import 'package:flutter/painting.dart' show TextDirection;
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/questionnaires/mock_fixtures.dart';
import 'package:koi_mobile/questionnaires/questionnaire_models.dart';
import 'package:koi_mobile/questionnaires/questionnaire_wire.dart';

import '../support/mob3_support.dart';

// MOB-6: rewritten for contract v0.5.2 (PatientQuestionnaireDTO). The
// MOB-3 AI-draft shape (status, body, language, rtl, help_text, sources,
// numeric, "rating") is gone; see the MOB-6 report for each change.

Map<String, Object?> _q(
  String type, {
  int options = 2,
  String id = 'q1',
  Object? required = true,
  Map<String, Object?> extra = const {},
}) => {
  'id': id,
  'type': type,
  'prompt': {'en': 'Placeholder'},
  'required': ?required,
  if (type != 'yes_no' && type != 'short_text')
    'options': [
      for (var i = 0; i < options; i++)
        {
          'id': 'o$i',
          'label': {'en': 'Option $i'},
        },
    ],
  if (type == 'short_text') 'max_length': 100,
  if (type == 'multi_choice') ...{'min_selections': 0, 'max_selections': 2},
  ...extra,
};

Map<String, Object?> _form(
  List<Map<String, Object?>> questions, {
  List<String> locales = const ['en'],
  Object? schemaVersion = '0.5.0',
}) => {
  'version_id': 'v1',
  'schema_version': schemaVersion,
  'title': {'en': 'T'},
  'locales': locales,
  'questions': questions,
};

Matcher get _refused => throwsA(
  anyOf(isA<UnsupportedQuestionnaireException>(), isA<FormatException>()),
);

void main() {
  group('MOB3-01 PatientQuestionnaireDTO parses every question type', () {
    test('the all-types fixture holds all 7 types with their fields', () {
      final q = parsePatientQuestionnaire(demoAllTypesEn());
      expect(
        q.questions.map((x) => x.type).toSet(),
        QuestionType.values.toSet(),
      );
      final multi = q.question('q_multi')!;
      expect([multi.minSelections, multi.maxSelections], [2, 3]);
      expect(q.question('q_short_text')!.maxLength, 500);
      expect(q.question('q_yes_no')!.options, isEmpty);
      expect(
        q.question('q_image_single')!.options.first.asset!.assetId,
        'placeholder_circle_v1',
      );
      expect(q.versionId, 'demo_version_en');
      expect(q.locales, [
        QuestionnaireLanguage.en,
        QuestionnaireLanguage.ur,
        QuestionnaireLanguage.romanUr,
      ]);
    });
    test('options keep their published order', () {
      final q = parsePatientQuestionnaire(_form([_q('likert', options: 4)]));
      expect(q.questions.single.options.map((o) => o.id), [
        'o0',
        'o1',
        'o2',
        'o3',
      ]);
    });
  });

  group('MOB3-02 malformed questionnaires are refused', () {
    final cases = <String, Map<String, Object?>>{
      'schema_version not 0.5.0': _form([
        _q('single_choice'),
      ], schemaVersion: '0.4'),
      'unknown locale': _form([_q('single_choice')], locales: ['fr']),
      'no locale': _form([_q('single_choice')], locales: []),
      'unknown type': _form([_q('slider')]),
      'the old "rating" type': _form([_q('rating')]),
      'the old "single" type': _form([_q('single')]),
      'no questions': _form([]),
      'duplicate question ids': _form([_q('single_choice'), _q('likert')]),
      'bad question id': _form([_q('single_choice', id: 'q 1')]),
      'id starting with a dash': _form([_q('single_choice', id: '-q1')]),
      'choice with one option': _form([_q('single_choice', options: 1)]),
      'more than 20 options': _form([_q('multi_choice', options: 21)]),
      'more than 200 questions': _form([
        for (var i = 0; i < 201; i++) _q('single_choice', id: 'q$i'),
      ]),
      'min_selections above max_selections': _form([
        _q(
          'multi_choice',
          options: 4,
          extra: {'min_selections': 3, 'max_selections': 2},
        ),
      ]),
      'multi without max_selections': _form([
        {..._q('multi_choice')}..remove('max_selections'),
      ]),
      'short_text without max_length': _form([
        {..._q('short_text')}..remove('max_length'),
      ]),
      'max_length above 4000': _form([
        _q('short_text', extra: {'max_length': 4001}),
      ]),
      'duplicate option ids': _form([
        {
          ..._q('single_choice'),
          'options': [
            {
              'id': 'a',
              'label': {'en': 'A'},
            },
            {
              'id': 'a',
              'label': {'en': 'B'},
            },
          ],
        },
      ]),
      'bad option id': _form([
        {
          ..._q('single_choice'),
          'options': [
            {
              'id': 'a/b',
              'label': {'en': 'A'},
            },
            {
              'id': 'b',
              'label': {'en': 'B'},
            },
          ],
        },
      ]),
      'plain-string prompt': _form([
        {..._q('single_choice'), 'prompt': 'Placeholder'},
      ]),
      'empty prompt': _form([
        {
          ..._q('single_choice'),
          'prompt': {'en': ''},
        },
      ]),
      'prompt in an unknown locale': _form([
        {
          ..._q('single_choice'),
          'prompt': {'fr': 'Bonjour'},
        },
      ]),
    };
    for (final e in cases.entries) {
      test(e.key, () {
        expect(() => parsePatientQuestionnaire(e.value), _refused);
      });
    }
  });

  group('MOB3-03 yes_no has no options; likert 2 to 11', () {
    test('yes_no', () {
      expect(
        () => parsePatientQuestionnaire(
          _form([
            {
              ..._q('yes_no'),
              'options': [
                {
                  'id': 'y',
                  'label': {'en': 'Y'},
                },
                {
                  'id': 'n',
                  'label': {'en': 'N'},
                },
              ],
            },
          ]),
        ),
        _refused,
      );
      expect(
        parsePatientQuestionnaire(_form([_q('yes_no')]))
            .questions
            .single
            .options,
        isEmpty,
      );
    });
    test('likert', () {
      for (final bad in [1, 12]) {
        expect(
          () => parsePatientQuestionnaire(_form([_q('likert', options: bad)])),
          _refused,
          reason: '$bad options',
        );
      }
      for (final ok in [2, 11]) {
        expect(
          parsePatientQuestionnaire(_form([_q('likert', options: ok)]))
              .questions
              .single
              .options,
          hasLength(ok),
        );
      }
    });
  });

  group('MOB3-04 required is mandatory; due_at is optional', () {
    test('required', () {
      expect(
        parsePatientQuestionnaire(_form([_q('single_choice')]))
            .questions
            .single
            .required,
        isTrue,
      );
      expect(
        parsePatientQuestionnaire(_form([_q('single_choice', required: false)]))
            .questions
            .single
            .required,
        isFalse,
      );
      for (final bad in [null, 'yes']) {
        expect(
          () => parsePatientQuestionnaire(
            _form([_q('single_choice', required: bad)]),
          ),
          _refused,
          reason: '$bad',
        );
      }
    });
    test('a text missing in a listed locale falls back in locale order', () {
      final q = parsePatientQuestionnaire(
        _form(
          [
            {
              ..._q('single_choice'),
              'prompt': {'ur': 'اردو'},
            },
          ],
          locales: ['ur', 'en'],
        ),
      );
      expect(
        q.questions.single.prompt.resolve(QuestionnaireLanguage.en),
        'اردو',
      );
    });
  });

  group(
    'MOB3-05 fields for the psychologist / evaluation are never parsed',
    () {
      test('a questionnaire carrying them is refused (strict v0.5.2)', () {
        expect(
          () => parsePatientQuestionnaire(allTypesWithHiddenFields()),
          _refused,
        );
      });
      test('no questionnaire source file reads those keys (code only)', () {
        final forbidden = RegExp(
          r"scoring_config|review_warnings|'category'|'validated'|\bband|interpret|evaluat|'weight'|reverse_scored|\bscore",
        );
        final hits = <String>[];
        for (final f in dartFilesUnder('lib/questionnaires')) {
          // The mock fixtures are the SERVER side of the demo and are
          // excluded.
          if (f.path.contains('mock_')) continue;
          final lines = codeOf(f).split('\n');
          for (var i = 0; i < lines.length; i++) {
            if (forbidden.hasMatch(lines[i])) hits.add('${f.path}:${i + 1}');
          }
        }
        expect(hits, isEmpty);
      });
    },
  );

  group('MOB3-06 direction follows the shown locale', () {
    test('ur → right-to-left; ur-Latn and en → left-to-right', () {
      expect(QuestionnaireLanguage.ur.direction, TextDirection.rtl);
      expect(QuestionnaireLanguage.romanUr.direction, TextDirection.ltr);
      expect(QuestionnaireLanguage.en.direction, TextDirection.ltr);
      expect(
        parsePatientQuestionnaire(demoUrdu()).defaultLanguage('en'),
        QuestionnaireLanguage.ur,
      );
      expect(
        parsePatientQuestionnaire(demoRomanUrdu()).defaultLanguage('ur'),
        QuestionnaireLanguage.romanUr,
      );
    });
  });

  group('MOB3-08 pictures are asset references, never URLs or paths', () {
    test('a URL or a malformed reference is refused (never loaded)', () {
      Map<String, Object?> withAsset(Object? asset) => _form([
        {
          ..._q('image_single_choice'),
          'options': [
            {
              'id': 'a',
              'label': {'en': 'A'},
              'asset': asset,
            },
            {
              'id': 'b',
              'label': {'en': 'B'},
              'asset': {'asset_id': 'b_pic', 'version': 1, 'sha256': 'a' * 64},
            },
          ],
        },
      ]);
      for (final bad in <Object?>[
        'https://example.com/a.png',
        {'asset_id': '../secret', 'version': 1, 'sha256': 'a' * 64},
        {'asset_id': 'a.png', 'version': 1, 'sha256': 'a' * 64},
        {'asset_id': 'ok', 'version': 0, 'sha256': 'a' * 64},
        {'asset_id': 'ok', 'version': 1, 'sha256': 'A' * 64},
        {'asset_id': 'ok', 'version': 1},
        {
          'asset_id': 'ok',
          'version': 1,
          'sha256': 'a' * 64,
          'url': 'https://example.com/a.png',
        },
        null,
      ]) {
        expect(
          () => parsePatientQuestionnaire(withAsset(bad)),
          _refused,
          reason: '$bad',
        );
      }
      expect(
        parsePatientQuestionnaire(
          withAsset({
            'asset_id': 'sleep_moon_01',
            'version': 2,
            'sha256': 'b' * 64,
          }),
        ).questions.single.options.first.asset,
        AssetReference(assetId: 'sleep_moon_01', version: 2, sha256: 'b' * 64),
      );
    });
    test('no lib file loads pictures from the network', () {
      final net = RegExp(r'Image\.network|NetworkImage|firebase_storage');
      final hits = [
        for (final f in dartFilesUnder('lib/questionnaires'))
          if (net.hasMatch(codeOf(f))) f.path,
      ];
      expect(hits, isEmpty);
      expect(
        File('pubspec.yaml').readAsStringSync(),
        isNot(contains('firebase_storage')),
      );
    });
  });
}
