import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart' show TextDirection;
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/questionnaires/mock_fixtures.dart';
import 'package:koi_mobile/questionnaires/questionnaire_models.dart';
import 'package:koi_mobile/questionnaires/questionnaire_wire.dart';

import '../support/mob3_support.dart';

/// Everything the parsed model holds, as JSON (to prove what is kept).
String dump(PublishedQuestionnaire q) => jsonEncode({
  'id': q.questionnaireId,
  'version': q.version,
  'title': q.title,
  'description': q.description,
  'language': q.language.wire,
  'rtl': q.rtl,
  'sources': [
    for (final s in q.sources) [s.sourceId, s.citation, s.attributionText],
  ],
  'questions': [
    for (final x in q.questions)
      {
        'id': x.id,
        'type': x.type.wire,
        'text': x.text,
        'help': x.helpText,
        'required': x.required,
        'min': x.minValue,
        'max': x.maxValue,
        'step': x.step,
        'asset': x.assetId,
        'visual': x.visualDescription,
        'options': [
          for (final o in x.options)
            [o.id, o.label, o.assetId, o.visualDescription],
        ],
      },
  ],
});

Map<String, Object?> _q(
  String type, {
  int options = 2,
  String id = 'q1',
  Object? required,
  Map<String, Object?> extra = const {},
}) => {
  'question_id': id,
  'type': type,
  'text': 'Placeholder',
  'required': ?required,
  'options': [
    for (var i = 0; i < options; i++)
      {'option_id': 'o$i', 'label': 'Option $i'},
  ],
  ...extra,
};

Map<String, Object?> _form(
  List<Map<String, Object?>> questions, {
  String language = 'en',
  bool? rtl,
  String status = 'published',
  Object? version = 1,
}) => {
  'questionnaire_id': 'form',
  'version': version,
  'status': status,
  'body': {
    'title': 'T',
    'language': language,
    'rtl': rtl ?? language == 'ur',
    'questions': questions,
  },
};

Matcher get _refused => throwsA(
  anyOf(isA<UnsupportedQuestionnaireException>(), isA<FormatException>()),
);

void main() {
  group('MOB3-01 PublishedQuestionnaire body parses every question type', () {
    test('the all-types fixture holds all 8 types with their fields', () {
      final q = parsePublishedQuestionnaire(demoAllTypesEn());
      expect(
        q.questions.map((x) => x.type).toSet(),
        QuestionType.values.toSet(),
      );
      final numeric = q.question('q_numeric')!;
      expect([numeric.minValue, numeric.maxValue, numeric.step], [0, 10, 1]);
      expect(q.question('q_multi')!.helpText, 'Choose one or more.');
      expect(q.question('q_image_single')!.assetId, 'placeholder_triangle_v1');
      expect(q.description, 'Placeholder description. Answer each item.');
      expect(q.questionnaireId, 'demo_all_types_en');
      expect(q.version, 1);
    });
    test('"rating" is read as likert; options keep their published order', () {
      final q = parsePublishedQuestionnaire(_form([_q('rating', options: 4)]));
      expect(q.questions.single.type, QuestionType.likert);
      expect(q.questions.single.options.map((o) => o.id), [
        'o0',
        'o1',
        'o2',
        'o3',
      ]);
    });
  });

  group('MOB3-02 malformed or unpublished questionnaires are refused', () {
    final cases = <String, Map<String, Object?>>{
      'not published': _form([_q('single')], status: 'draft'),
      'version 0': _form([_q('single')], version: 0),
      'unknown language': _form([_q('single')], language: 'fr'),
      'ur but rtl false': _form([_q('single')], language: 'ur', rtl: false),
      'en but rtl true': _form([_q('single')], rtl: true),
      'unknown type': _form([_q('slider')]),
      'no questions': _form([]),
      'duplicate question ids': _form([_q('single'), _q('multi')]),
      'bad question id': _form([_q('single', id: 'q 1')]),
      'choice without options': _form([_q('single', options: 0)]),
      'more than 12 options': _form([_q('multi', options: 13)]),
      'more than 100 questions': _form([
        for (var i = 0; i < 101; i++) _q('single', id: 'q$i'),
      ]),
      'min above max': _form([
        _q('numeric', options: 0, extra: {'min_value': 5, 'max_value': 1}),
      ]),
      'step 0': _form([
        _q('numeric', options: 0, extra: {'step': 0}),
      ]),
      'duplicate option ids': _form([
        {
          ..._q('single'),
          'options': [
            {'option_id': 'a', 'label': 'A'},
            {'option_id': 'a', 'label': 'B'},
          ],
        },
      ]),
      'bad option id': _form([
        {
          ..._q('single'),
          'options': [
            {'option_id': 'a/b', 'label': 'A'},
          ],
        },
      ]),
      'no body': {'questionnaire_id': 'f', 'version': 1, 'status': 'published'},
    };
    for (final e in cases.entries) {
      test(e.key, () {
        expect(() => parsePublishedQuestionnaire(e.value), _refused);
      });
    }
  });

  group('MOB3-03 yes_no has exactly 2 options; likert 3 to 7', () {
    test('yes_no', () {
      expect(
        () => parsePublishedQuestionnaire(_form([_q('yes_no', options: 1)])),
        _refused,
      );
      expect(
        () => parsePublishedQuestionnaire(_form([_q('yes_no', options: 3)])),
        _refused,
      );
      expect(
        parsePublishedQuestionnaire(_form([_q('yes_no')]))
            .questions
            .single
            .options,
        hasLength(2),
      );
    });
    test('likert', () {
      for (final bad in [2, 8]) {
        expect(
          () =>
              parsePublishedQuestionnaire(_form([_q('likert', options: bad)])),
          _refused,
          reason: '$bad options',
        );
      }
      for (final ok in [3, 7]) {
        expect(
          parsePublishedQuestionnaire(_form([_q('likert', options: ok)]))
              .questions
              .single
              .options,
          hasLength(ok),
        );
      }
    });
  });

  group('MOB3-04 required defaults to true; optional texts may be absent', () {
    test('required', () {
      expect(
        parsePublishedQuestionnaire(_form([_q('single')]))
            .questions
            .single
            .required,
        isTrue,
      );
      expect(
        parsePublishedQuestionnaire(_form([_q('single', required: false)]))
            .questions
            .single
            .required,
        isFalse,
      );
      expect(
        () =>
            parsePublishedQuestionnaire(_form([_q('single', required: 'yes')])),
        _refused,
      );
    });
    test('description, help_text and visual descriptions are optional', () {
      final q = parsePublishedQuestionnaire(_form([_q('single')]));
      expect(q.description, isNull);
      expect(q.questions.single.helpText, isNull);
      expect(q.questions.single.visualDescription, isNull);
      expect(q.sources, isEmpty);
    });
  });

  group(
    'MOB3-05 fields for the psychologist / evaluation are never parsed',
    () {
      test('a body full of hidden fields parses to exactly the same model', () {
        expect(
          dump(parsePublishedQuestionnaire(allTypesWithHiddenFields())),
          dump(parsePublishedQuestionnaire(demoAllTypesEn())),
        );
        expect(
          dump(parsePublishedQuestionnaire(allTypesWithHiddenFields())),
          isNot(contains(psychologistOnlyMarker)),
        );
      });
      test('no questionnaire source file reads those keys (code only)', () {
        final forbidden = RegExp(
          r"scoring_config|review_warnings|'category'|'validated'|\bband|interpret|evaluat|'weight'|reverse_scored|\bscore",
        );
        final hits = <String>[];
        for (final f in dartFilesUnder('lib/questionnaires')) {
          // The mock fixtures are the SERVER side of the demo (they contain a
          // realistic body, including category/validated) and are excluded.
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

  group(
    'MOB3-06 direction follows the questionnaire, not the language name',
    () {
      test('ur → right-to-left; roman_ur and en → left-to-right', () {
        expect(
          parsePublishedQuestionnaire(demoUrdu()).direction,
          TextDirection.rtl,
        );
        expect(
          parsePublishedQuestionnaire(demoUrdu()).language,
          QuestionnaireLanguage.ur,
        );
        expect(
          parsePublishedQuestionnaire(demoRomanUrdu()).direction,
          TextDirection.ltr,
        );
        expect(
          parsePublishedQuestionnaire(demoRomanUrdu()).language,
          QuestionnaireLanguage.romanUr,
        );
        expect(
          parsePublishedQuestionnaire(demoAllTypesEn()).direction,
          TextDirection.ltr,
        );
      });
    },
  );

  group('MOB3-07 sources keep citation and attribution only', () {
    test(
      'WHO-5 attribution is kept word for word; bad sources are skipped',
      () {
        final who5 = parsePublishedQuestionnaire(who5Published());
        final s = who5.sources.single;
        expect(s.sourceId, 'who5_en_2024');
        expect(
          s.citation,
          'World Health Organization. The World Health Organization-Five '
          'Well-Being Index (WHO-5). Geneva: World Health Organization; 2024. '
          'License: CC-BY-NC-SA 3.0 IGO',
        );
        expect(s.attributionText, '© WHO, 2024. License: CC-BY-NC-SA 3.0 IGO');
        final form = _form([_q('single')]);
        (form['body']! as Map)['sources'] = [
          {'source_id': 'bad id', 'citation': 'x'},
          'not a map',
          {'source_id': 'ok', 'attribution_text': 'Attribution'},
        ];
        final parsed = parsePublishedQuestionnaire(form);
        expect(parsed.sources.map((x) => x.sourceId), ['ok']);
        expect(parsed.sources.single.citation, isNull);
      },
    );
  });

  group('MOB3-08 asset ids are ids, never URLs or paths', () {
    test('a URL or path is treated as unknown (never loaded)', () {
      Question parsedWith(Object? asset) => parsePublishedQuestionnaire(
        _form([
          {
            ..._q('image_single'),
            'options': [
              {
                'option_id': 'a',
                'label': 'A',
                'asset_id': asset,
                'visual_description': 'A drawn sun',
              },
              {'option_id': 'b', 'label': 'B'},
            ],
          },
        ]),
      ).questions.single;
      for (final bad in [
        'https://example.com/a.png',
        '../secret',
        'a.png',
        'x' * 129,
        42,
      ]) {
        final o = parsedWith(bad).options.first;
        expect(o.assetId, isNull, reason: '$bad');
        expect(o.visualDescription, 'A drawn sun');
      }
      expect(
        parsedWith('sleep_moon_01').options.first.assetId,
        'sleep_moon_01',
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
