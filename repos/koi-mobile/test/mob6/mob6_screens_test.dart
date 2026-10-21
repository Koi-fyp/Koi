import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/care/care_strings.dart';
import 'package:koi_mobile/questionnaires/mock_fixtures.dart';
import 'package:koi_mobile/questionnaires/mock_questionnaire_api.dart';
import 'package:koi_mobile/questionnaires/questionnaire_models.dart';
import 'package:koi_mobile/questionnaires/questionnaire_screens.dart';
import 'package:koi_mobile/questionnaires/questionnaire_wire.dart';

import '../support/mob3_support.dart';
import '../support/real_fonts.dart';

final _en = parsePatientQuestionnaire(demoAllTypesEn());

TextDirection _directionOf(WidgetTester tester, String questionId) => tester
    .widget<Directionality>(
      find
          .ancestor(
            of: find.byKey(Key('question-$questionId')),
            matching: find.byType(Directionality),
          )
          .first,
    )
    .textDirection;

String? _familyOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text).first).style?.fontFamily;

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  useRealFonts();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  final seedEn = MockQuestionnaireRemote.demoSeeds()[0];

  group('MOB6-14 language chips: only with several locales', () {
    testWidgets('English by default; Urdu → RTL Nastaliq; Roman Urdu → LTR', (
      tester,
    ) async {
      await pumpRunnerFor(tester, MockQuestionnaireRemote(), seedEn);
      expect(find.byKey(const Key('q-languages')), findsOneWidget);
      for (final l in ['en', 'ur', 'ur-Latn']) {
        final chip = find.byKey(Key('q-lang-$l'));
        expect(tester.getSize(chip).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(chip).width, greaterThanOrEqualTo(48));
      }
      expect(
        tester
            .getSemantics(find.byKey(const Key('q-lang-en')))
            .flagsCollection
            .isChecked,
        CheckedState.isTrue,
      );
      expect(find.text('Placeholder single choice'), findsOneWidget);
      expect(_directionOf(tester, 'q_single'), TextDirection.ltr);

      await _tap(tester, 'q-lang-ur');
      expect(_directionOf(tester, 'q_single'), TextDirection.rtl);
      expect(find.text('نمونہ سوال ایک'), findsOneWidget);
      expect(_familyOf(tester, 'نمونہ سوال ایک'), contains('NotoNastaliqUrdu'));
      expect(_familyOf(tester, 'اختیار الف'), contains('NotoNastaliqUrdu'));
      expect(
        tester
            .getSemantics(find.byKey(const Key('q-lang-ur')))
            .flagsCollection
            .isChecked,
        CheckedState.isTrue,
      );

      await _tap(tester, 'q-lang-ur-Latn');
      expect(_directionOf(tester, 'q_single'), TextDirection.ltr);
      expect(find.text('Namoona sawal ek'), findsOneWidget);
      expect(_familyOf(tester, 'Namoona sawal ek'), contains('DMSans'));
    });
    testWidgets('the Settings language Urdu opens the Urdu text', (
      tester,
    ) async {
      await pumpRunnerFor(
        tester,
        MockQuestionnaireRemote(),
        seedEn,
        settingsLanguage: 'ur',
      );
      expect(_directionOf(tester, 'q_single'), TextDirection.rtl);
      expect(find.text('نمونہ سوال ایک'), findsOneWidget);
    });
    testWidgets('a one-locale questionnaire has no chips', (tester) async {
      await pumpRunnerFor(
        tester,
        MockQuestionnaireRemote(),
        MockQuestionnaireRemote.demoSeeds()[1],
      );
      expect(find.byKey(const Key('q-languages')), findsNothing);
      expect(_directionOf(tester, 'q_single'), TextDirection.rtl);
    });
  });

  group('MOB6-15 yes / no follow the shown language', () {
    testWidgets('Yes/No, ہاں/نہیں, Haan/Nahin; the summary agrees', (
      tester,
    ) async {
      await pumpRunnerFor(tester, MockQuestionnaireRemote(), seedEn);
      await answerAndNext(tester, _en.question('q_single')!);
      await answerAndNext(tester, _en.question('q_multi')!);
      expect(find.text('Yes'), findsOneWidget);
      await _tap(tester, 'q-lang-ur');
      expect(find.text('ہاں'), findsOneWidget);
      expect(find.text('نہیں'), findsOneWidget);
      await _tap(tester, 'q-lang-ur-Latn');
      expect(find.text('Haan'), findsOneWidget);
      await _tap(tester, 'option-no');
      await _tap(tester, 'q-next');
      for (final q in _en.questions.skip(3)) {
        await answerAndNext(tester, q);
      }
      // q_yes_no answered "no" → shown as "Nahin" in Roman Urdu.
      expect(
        tester.widget<Text>(find.byKey(const Key('summary-q_yes_no'))).data,
        'Nahin',
      );
    });
  });

  group('MOB6-16 multiple choice limits (min / max selections)', () {
    testWidgets('hint, below-minimum message, blocked Next, disabled at max', (
      tester,
    ) async {
      final r = MockQuestionnaireRemote();
      await pumpRunnerFor(tester, r, seedEn);
      await answerAndNext(tester, _en.question('q_single')!);
      expect(find.text('Choose at least 2 · Choose up to 3'), findsOneWidget);
      await _tap(tester, 'option-o_a');
      expect(find.byKey(const Key('multi-below-min')), findsOneWidget);
      await _tap(tester, 'q-next');
      expect(find.text('Please answer this question.'), findsOneWidget);
      expect(find.byKey(const Key('question-q_multi')), findsOneWidget);
      // Never sent while below the minimum.
      expect(
        r.autosaveBodies
            .expand((b) => b['answers']! as List)
            .where((a) => (a as Map)['question_id'] == 'q_multi'),
        isEmpty,
      );
      await _tap(tester, 'option-o_b');
      expect(find.byKey(const Key('multi-below-min')), findsNothing);
      await _tap(tester, 'option-o_c');
      final d = tester.getSemantics(find.byKey(const Key('option-o_d')));
      expect(d.flagsCollection.isEnabled, Tristate.isFalse);
      await _tap(tester, 'option-o_d');
      expect(
        tester
            .getSemantics(find.byKey(const Key('option-o_d')))
            .flagsCollection
            .isChecked,
        CheckedState.isFalse,
      );
      await tester.pump(const Duration(seconds: 1)); // autosave debounce
      await tester.pumpAndSettle();
      expect(
        r.autosaveBodies.last['answers'],
        contains(
          equals({
            'question_id': 'q_multi',
            'type': 'multi_choice',
            'value': ['o_a', 'o_b', 'o_c'],
          }),
        ),
      );
    });
    testWidgets('the limits read in Urdu with the Settings language Urdu', (
      tester,
    ) async {
      await pumpRunnerFor(
        tester,
        MockQuestionnaireRemote(),
        seedEn,
        settingsLanguage: 'ur',
      );
      await answerAndNext(tester, _en.question('q_single')!);
      expect(
        find.text(
          '${CareStrings.ur.chooseAtLeast(2)} · ${CareStrings.ur.chooseUpTo(3)}',
        ),
        findsOneWidget,
      );
    });
  });

  group('MOB6-17 320 and 360 dp: no overflow, English and Urdu', () {
    for (final width in [320.0, 360.0]) {
      for (final lang in ['en', 'ur']) {
        testWidgets(
          '${width.toInt()} dp, Settings $lang, every type to submit',
          (tester) async {
            await pumpRunnerFor(
              tester,
              MockQuestionnaireRemote(),
              seedEn,
              settingsLanguage: lang,
              widthDp: width,
            );
            for (final q in _en.questions) {
              await answerAndNext(tester, q);
            }
            await _tap(tester, 'q-submit');
            expect(find.byKey(const Key('ack-title')), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });

  group('MOB6-18 demo flow: what reaches the (demo) server is v0.5.2', () {
    testWidgets('every PATCH body, the stored answers, then only the ack', (
      tester,
    ) async {
      final r = MockQuestionnaireRemote();
      await pumpRunnerFor(tester, r, seedEn);
      for (final q in _en.questions) {
        await answerAndNext(tester, q);
      }
      await _tap(tester, 'q-submit');
      expect(find.text(AcknowledgementView.title), findsOneWidget);
      expect(r.autosaveBodies, isNotEmpty);
      for (final body in r.autosaveBodies) {
        expect(body.keys.toSet(), {'expected_revision', 'answers'});
        for (final a in body['answers']! as List) {
          expect((a as Map).keys.toSet(), {'question_id', 'type', 'value'});
        }
      }
      final stored = r.answersOf(seedEn.attemptId);
      expect(answerIssues(_en.questions, stored, isFinal: true), isEmpty);
      expect(r.committedSubmissions, 1);
      for (final word in ['score', 'evaluation', 'review', 'job']) {
        expect(
          find.textContaining(RegExp(word, caseSensitive: false)),
          findsNothing,
          reason: word,
        );
      }
    });
  });

  group('MOB6-19 real-server pictures without a bundled match show text', () {
    testWidgets('labels as text tiles; answerable; nothing loaded', (
      tester,
    ) async {
      // The web's illustration references (shape_*, SVG on the web): not
      // bundled in the app, so the labels are shown.
      Map<String, Object?> shape(String id, String label) => {
        'id': id,
        'label': {'en': label},
        'asset': {'asset_id': 'shape_$id', 'version': 1, 'sha256': 'c' * 64},
      };
      final seed = seedFor({
        'version_id': 'x',
        'schema_version': '0.5.0',
        'title': {'en': 'Pictures'},
        'locales': ['en'],
        'questions': [
          {
            'id': 'q_pic',
            'type': 'image_multi_choice',
            'prompt': {'en': 'Pick shapes'},
            'required': true,
            'min_selections': 1,
            'max_selections': 2,
            'options': [shape('circle', 'Circle'), shape('square', 'Square')],
          },
        ],
      });
      final r = MockQuestionnaireRemote(seeds: [seed]);
      await pumpRunnerFor(tester, r, seed);
      expect(find.byType(Image), findsNothing);
      expect(find.text('Circle'), findsOneWidget);
      expect(find.text('Square'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('option-circle'))).height,
        greaterThanOrEqualTo(48),
      );
      await _tap(tester, 'option-square');
      await tester.pump(const Duration(seconds: 1));
      expect(r.answersOf(seed.attemptId).single.value, ['square']);
    });
  });
}
