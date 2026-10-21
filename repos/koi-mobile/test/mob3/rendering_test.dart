import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/care/care_strings.dart';
import 'package:koi_mobile/platform/demo_badge.dart';
import 'package:koi_mobile/questionnaires/mock_fixtures.dart';
import 'package:koi_mobile/questionnaires/mock_questionnaire_api.dart';
import 'package:koi_mobile/questionnaires/questionnaire_api.dart';
import 'package:koi_mobile/questionnaires/questionnaire_models.dart';
import 'package:koi_mobile/questionnaires/questionnaire_providers.dart';
import 'package:koi_mobile/questionnaires/questionnaire_screens.dart';
import 'package:koi_mobile/questionnaires/questionnaire_wire.dart';

import '../support/mob1_fakes.dart';
import '../support/mob3_support.dart';
import '../support/real_fonts.dart';

/// Every string currently drawn by a Text / RichText.
List<String> _texts(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(find.byType(Text)))
    t.data ?? t.textSpan?.toPlainText() ?? '',
];

String? _familyOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text).first).style?.fontFamily;

/// No questionnaire wording may be cut: no maxLines, no ellipsis, and the
/// painted paragraph did not run out of lines.
void _expectNothingTruncated(WidgetTester tester) {
  for (final t in tester.widgetList<Text>(find.byType(Text))) {
    expect(t.maxLines, isNull, reason: '${t.data}');
    expect(t.overflow, isNot(TextOverflow.ellipsis), reason: '${t.data}');
  }
  for (final p in tester.renderObjectList<RenderParagraph>(
    find.byType(RichText),
  )) {
    expect(p.didExceedMaxLines, isFalse);
  }
}

/// Walks a whole questionnaire in the runner and checks every question
/// text and option label is on screen EXACTLY as published.
Future<void> _walkWordForWord(
  WidgetTester tester,
  PublishedQuestionnaire q,
) async {
  const en = QuestionnaireLanguage.en;
  expect(find.text(q.title.resolve(en)), findsOneWidget, reason: 'title');
  for (final question in q.questions) {
    expect(
      find.text(question.prompt.resolve(en)),
      findsOneWidget,
      reason: question.id,
    );
    for (final o in question.options) {
      expect(
        find.text(o.label.resolve(en)),
        findsOneWidget,
        reason: '${question.id}/${o.id}',
      );
    }
    // Options in the published order (top to bottom).
    final ys = [
      for (final o in question.options)
        tester.getTopLeft(find.byKey(Key('option-${o.id}'))).dy,
    ];
    expect(ys, [...ys]..sort(), reason: '${question.id} order');
    _expectNothingTruncated(tester);
    await answerAndNext(tester, question);
  }
  expect(find.text('Check your answers'), findsOneWidget);
}

void main() {
  useRealFonts();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  final en = parsePatientQuestionnaire(demoAllTypesEn());

  // MOB-6: the seven v0.5.2 types (numeric is gone; yes_no has no options).
  group('MOB3-30 each question type gets its widget', () {
    testWidgets('radio / checkbox / two buttons / text / pictures', (
      tester,
    ) async {
      final r = MockQuestionnaireRemote();
      await pumpRunnerFor(tester, r, MockQuestionnaireRemote.demoSeeds()[0]);
      SemanticsNode node(String option) =>
          tester.getSemantics(find.byKey(Key('option-$option')));

      // single: radio group
      expect(node('o_a').flagsCollection.isInMutuallyExclusiveGroup, isTrue);
      await answerAndNext(tester, en.question('q_single')!);
      // multi: checkboxes (not exclusive) with their limits
      expect(node('o_a').flagsCollection.isInMutuallyExclusiveGroup, isFalse);
      expect(find.text('Choose at least 2 · Choose up to 3'), findsOneWidget);
      await answerAndNext(tester, en.question('q_multi')!);
      // yes_no: two buttons side by side
      final yes = tester.getRect(find.byKey(const Key('option-yes')));
      final no = tester.getRect(find.byKey(const Key('option-no')));
      expect(yes.top, no.top);
      expect(no.left, greaterThan(yes.right));
      expect(node('yes').flagsCollection.isButton, isTrue);
      expect(find.text('Yes'), findsOneWidget);
      expect(find.text('No'), findsOneWidget);
      await answerAndNext(tester, en.question('q_yes_no')!);
      // likert: ordered exclusive scale
      expect(node('o1').flagsCollection.isInMutuallyExclusiveGroup, isTrue);
      await answerAndNext(tester, en.question('q_likert')!);
      // short_text: a text field with its own max_length counter
      expect(find.byKey(const Key('free-text')), findsOneWidget);
      expect(find.text('0 / 500'), findsOneWidget);
      await answerAndNext(tester, en.question('q_short_text')!);
      // image: picture tiles
      expect(find.byKey(const Key('image-img_circle')), findsOneWidget);
      expect(find.byType(Image), findsWidgets);
    });
  });

  group('MOB3-31 WHO-5 (English) is shown word for word (test fixture)', () {
    // MOB-6: v0.5.2 has no instructions text (description).
    testWidgets('title, items, labels and order', (tester) async {
      final who5 = parsePatientQuestionnaire(who5Published());
      await pumpRunnerFor(
        tester,
        MockQuestionnaireRemote(seeds: [seedFor(who5Published())]),
        seedFor(who5Published()),
      );
      expect(
        find.text('I have felt cheerful and in good spirits'),
        findsOneWidget,
      );
      await _walkWordForWord(tester, who5);
    });
  });

  group('MOB3-32 DASS-21 (English) is shown word for word (test fixture)', () {
    testWidgets('all 21 items and labels; published spaces are never trimmed', (
      tester,
    ) async {
      final dass = parsePatientQuestionnaire(dass21Published());
      expect(
        dass.title.resolve(QuestionnaireLanguage.en),
        'Depression Anxiety Stress Scales (DASS21)',
      );
      expect(dass.questions, hasLength(21));
      await pumpRunnerFor(
        tester,
        MockQuestionnaireRemote(seeds: [seedFor(dass21Published())]),
        seedFor(dass21Published()),
      );
      await _walkWordForWord(tester, dass);
      // Wording is never trimmed: a published trailing space stays.
      final spaced = dass21Published();
      ((spaced['questions']! as List)[0] as Map)['prompt'] = {
        'en': 'I found it hard to wind down ',
      };
      expect(
        parsePatientQuestionnaire(spaced).questions.first.prompt
            .resolve(QuestionnaireLanguage.en),
        'I found it hard to wind down ',
      );
    });
  });

  group('MOB3-33 Urdu: right-to-left, Nastaliq for the wording only', () {
    testWidgets(
      'content in Noto Nastaliq Urdu; buttons and status keep the app font',
      (tester) async {
        final r = MockQuestionnaireRemote();
        await pumpRunnerFor(tester, r, MockQuestionnaireRemote.demoSeeds()[1]);
        final dir = tester.widget<Directionality>(
          find
              .ancestor(
                of: find.byKey(const Key('question-q_single')),
                matching: find.byType(Directionality),
              )
              .first,
        );
        expect(dir.textDirection, TextDirection.rtl);
        for (final t in ['نمونہ فارم (اردو)', 'نمونہ سوال ایک', 'اختیار الف']) {
          expect(_familyOf(tester, t), contains('NotoNastaliqUrdu'), reason: t);
        }
        expect(_familyOf(tester, 'Next'), isNot(contains('NotoNastaliqUrdu')));
        expect(_familyOf(tester, 'Question 1 of 5'), contains('DMSans'));
        // The Next button sits on the LEFT in right-to-left layout.
        expect(
          tester.getCenter(find.byKey(const Key('q-next'))).dx,
          lessThan(tester.getCenter(find.byKey(const Key('q-previous'))).dx),
        );
      },
    );
    testWidgets(
      'with the Settings language Urdu, the chrome is Urdu (system font)',
      (tester) async {
        await pumpRunnerFor(
          tester,
          MockQuestionnaireRemote(),
          MockQuestionnaireRemote.demoSeeds()[1],
          settingsLanguage: 'ur',
        );
        expect(find.text(CareStrings.ur.t(CareText.qNext)), findsOneWidget);
        expect(
          _familyOf(tester, CareStrings.ur.t(CareText.qNext)),
          isNot(contains('NotoNastaliqUrdu')),
        );
      },
    );
  });

  group('MOB3-34 Roman Urdu is left-to-right Latin with the app font', () {
    testWidgets('no Nastaliq anywhere', (tester) async {
      await pumpRunnerFor(
        tester,
        MockQuestionnaireRemote(),
        MockQuestionnaireRemote.demoSeeds()[2],
      );
      final dir = tester.widget<Directionality>(
        find
            .ancestor(
              of: find.byKey(const Key('question-q_single')),
              matching: find.byType(Directionality),
            )
            .first,
      );
      expect(dir.textDirection, TextDirection.ltr);
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        expect(
          t.style?.fontFamily ?? '',
          isNot(contains('NotoNastaliqUrdu')),
          reason: t.data,
        );
      }
      expect(_familyOf(tester, 'Namoona sawal ek'), contains('DMSans'));
    });
  });

  // MOB3-35 (sources attribution) is retired: contract v0.5.2 has no
  // sources field (replacement: MOB6-07).

  group('MOB3-36 nothing for the psychologist ever reaches the screen', () {
    // MOB-6: strict v0.5.2, such a questionnaire is refused outright.
    testWidgets(
      'a questionnaire carrying such fields shows only the safe message',
      (tester) async {
        final seed = seedFor(allTypesWithHiddenFields());
        await pumpRunnerFor(
          tester,
          MockQuestionnaireRemote(seeds: [seed]),
          seed,
        );
        expect(
          find.text(CareStrings.en.t(CareText.qUnsupported)),
          findsOneWidget,
        );
        expect(find.byKey(const Key('question-q_single')), findsNothing);
        for (final t in _texts(tester)) {
          for (final bad in [
            psychologistOnlyMarker,
            'cfg_secret',
            'Placeholder',
          ]) {
            expect(t, isNot(contains(bad)), reason: t);
          }
        }
      },
    );
  });

  group('MOB3-37 after submit: only "Response submitted" (+ time)', () {
    testWidgets('nothing else is shown or fetched', (tester) async {
      final r = MockQuestionnaireRemote();
      await pumpRunnerFor(tester, r, MockQuestionnaireRemote.demoSeeds()[2]);
      for (final q in parsePatientQuestionnaire(demoRomanUrdu()).questions) {
        await answerAndNext(tester, q);
      }
      await tester.ensureVisible(find.byKey(const Key('q-submit')));
      await tester.tap(find.byKey(const Key('q-submit')));
      await tester.pumpAndSettle();
      final shown = _texts(tester).toSet()..remove(DemoDataBadge.label);
      expect(shown, hasLength(3));
      expect(shown, contains('Response submitted'));
      expect(shown, contains('Back to questionnaires'));
      expect(shown.where((t) => t.startsWith('Submitted at ')), hasLength(1));
    });
  });

  group(
    'MOB3-38 no AI route, URL, job or result anywhere on the patient side',
    () {
      test('lib never names an AI route, the AI service or its port', () {
        final ai = RegExp(
          r'/api/v1/ai|/ai/|evaluations/|/jobs/|:8100|KOI_AI|agentrouter|deepseek|ai_jobs|ai_scores|ai_interpretations',
          caseSensitive: false,
        );
        final hits = [
          for (final f in dartFilesUnder('lib'))
            if (ai.hasMatch(codeOf(f))) f.path,
        ];
        expect(hits, isEmpty);
      });
      test('questionnaire and notification strings never mention results', () {
        final words = RegExp(
          r'score|result|band|interpret|evaluat|diagnos|\bAI\b|job|review|severity',
          caseSensitive: false,
        );
        for (final lang in CareLang.values) {
          for (final e in CareStrings.table(lang).entries) {
            if (!e.key.name.startsWith('q') && !e.key.name.startsWith('kind')) {
              continue;
            }
            expect(
              words.hasMatch(e.value),
              isFalse,
              reason: '${e.key}: ${e.value}',
            );
          }
        }
      });
    },
  );

  group('MOB3-39 360dp: no overflow in English, Urdu and Roman Urdu', () {
    for (final (i, lang) in [(0, null), (1, 'ur'), (2, null), (0, 'ur')]) {
      testWidgets('demo ${MockQuestionnaireRemote.demoSeeds()[i].assignmentId} '
          '(Settings ${lang ?? 'en'})', (tester) async {
        final r = MockQuestionnaireRemote();
        final seed = MockQuestionnaireRemote.demoSeeds()[i];
        await pumpRunnerFor(tester, r, seed, settingsLanguage: lang);
        for (final q in parsePatientQuestionnaire(
          seed.questionnaire,
        ).questions) {
          await answerAndNext(tester, q);
        }
        expect(find.byKey(const Key('q-submit')), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('q-submit')));
        await tester.tap(find.byKey(const Key('q-submit')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('ack-title')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group(
    'MOB3-40 Demo data badge with mocks; Unavailable without a platform',
    () {
      testWidgets('mocks: the runner shows "Demo data"', (tester) async {
        await pumpRunnerFor(
          tester,
          MockQuestionnaireRemote(),
          MockQuestionnaireRemote.demoSeeds()[0],
        );
        expect(find.byType(DemoDataBadge), findsOneWidget);
      });
      testWidgets(
        'no KOI_PLATFORM_BASE and no mocks: Unavailable, no fake data',
        (tester) async {
          final h = Mob1Harness(
            user: AccountFakeAuth.registered('p1', 'p@x'),
            caps: {'p1': patientCaps},
          );
          late QuestionnaireApi api;
          await tester.pumpWidget(
            ProviderScope(
              overrides: h.overrides,
              child: MaterialApp(
                home: Consumer(
                  builder: (context, ref, _) {
                    api = ref.watch(questionnaireApiProvider);
                    return const QuestionnaireListScreen();
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(api, isA<UnavailableQuestionnaireApi>());
          expect(
            find.text(CareStrings.en.t(CareText.notAvailableYet)),
            findsOneWidget,
          );
          expect(find.byType(DemoDataBadge), findsNothing);
          expect(find.textContaining('Placeholder'), findsNothing);
        },
      );
    },
  );

  // MOB3-41 (help text and the question picture) is retired: contract
  // v0.5.2 has neither (replacement: MOB6-19, MOB6-07).

  group('MOB3-42 required multi needs its minimum; yes_no keeps one', () {
    testWidgets('validation and single selection', (tester) async {
      final r = MockQuestionnaireRemote();
      await pumpRunnerFor(tester, r, MockQuestionnaireRemote.demoSeeds()[0]);
      await answerAndNext(tester, en.question('q_single')!);
      await tester.tap(find.byKey(const Key('option-o_a')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('option-o_a'))); // unselected again
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('q-next')));
      await tester.tap(find.byKey(const Key('q-next')));
      await tester.pump();
      expect(find.text('Please answer this question.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('option-o_b')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('option-o_c')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('q-next')));
      await tester.tap(find.byKey(const Key('q-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('option-yes')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('option-no')));
      await tester.pump();
      final yes = tester.getSemantics(find.byKey(const Key('option-yes')));
      final no = tester.getSemantics(find.byKey(const Key('option-no')));
      expect(yes.flagsCollection.isChecked, CheckedState.isFalse);
      expect(no.flagsCollection.isChecked, CheckedState.isTrue);
    });
  });
}
