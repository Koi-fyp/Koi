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
  expect(find.text(q.title), findsOneWidget, reason: 'title');
  if (q.description != null) {
    expect(find.text(q.description!), findsOneWidget, reason: 'description');
  }
  for (final question in q.questions) {
    expect(find.text(question.text), findsOneWidget, reason: question.id);
    for (final o in question.options) {
      expect(
        find.text(o.label),
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

  final en = parsePublishedQuestionnaire(demoAllTypesEn());

  group('MOB3-30 each question type gets its widget', () {
    testWidgets('radio / checkbox / two buttons / text / number / pictures', (
      tester,
    ) async {
      final r = MockQuestionnaireRemote();
      await pumpRunnerFor(tester, r, MockQuestionnaireRemote.demoSeeds()[0]);
      SemanticsNode node(String option) =>
          tester.getSemantics(find.byKey(Key('option-$option')));

      // single: radio group
      expect(node('o_a').flagsCollection.isInMutuallyExclusiveGroup, isTrue);
      await answerAndNext(tester, en.question('q_single')!);
      // multi: checkboxes (not exclusive)
      expect(node('o_a').flagsCollection.isInMutuallyExclusiveGroup, isFalse);
      await answerAndNext(tester, en.question('q_multi')!);
      // yes_no: two buttons side by side
      final yes = tester.getRect(find.byKey(const Key('option-o_yes')));
      final no = tester.getRect(find.byKey(const Key('option-o_no')));
      expect(yes.top, no.top);
      expect(no.left, greaterThan(yes.right));
      expect(node('o_yes').flagsCollection.isButton, isTrue);
      await answerAndNext(tester, en.question('q_yes_no')!);
      // likert: ordered exclusive scale
      expect(node('o1').flagsCollection.isInMutuallyExclusiveGroup, isTrue);
      await answerAndNext(tester, en.question('q_likert')!);
      // free_text: a text field with a counter
      expect(find.byKey(const Key('free-text')), findsOneWidget);
      expect(find.text('0 / 4000'), findsOneWidget);
      await answerAndNext(tester, en.question('q_free_text')!);
      // numeric: field + stepper; range shown; invalid input explained
      expect(find.byKey(const Key('numeric-input')), findsOneWidget);
      expect(find.text('From 0 to 10'), findsOneWidget);
      await tester.tap(find.byKey(const Key('numeric-increase')));
      await tester.pump();
      expect(find.text('0'), findsOneWidget, reason: 'starts at min');
      await tester.tap(find.byKey(const Key('numeric-increase')));
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('numeric-input')),
          matching: find.byType(TextField),
        ),
        '11',
      );
      await tester.pump();
      expect(find.text('The highest allowed number is 10.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('q-next')));
      await tester.pump();
      expect(find.text('Please answer this question.'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('numeric-input')),
          matching: find.byType(TextField),
        ),
        '3',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('q-next')));
      await tester.pumpAndSettle();
      // image: picture tiles
      expect(find.byKey(const Key('image-img_circle')), findsOneWidget);
      expect(find.byType(Image), findsWidgets);
    });
  });

  group('MOB3-31 WHO-5 (English) is shown word for word (test fixture)', () {
    testWidgets('title, instructions, items, labels and order', (tester) async {
      final who5 = parsePublishedQuestionnaire(who5Published());
      await pumpRunnerFor(
        tester,
        MockQuestionnaireRemote(seeds: [seedFor(who5Published())]),
        seedFor(who5Published()),
      );
      expect(
        find.text(
          'Please indicate for each of the five statements which is closest to '
          'how you have been feeling over the last two weeks. Notice that '
          'higher numbers mean better well-being.',
        ),
        findsOneWidget,
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
      final dass = parsePublishedQuestionnaire(dass21Published());
      expect(dass.title, 'Depression Anxiety Stress Scales (DASS21)');
      expect(dass.questions, hasLength(21));
      await pumpRunnerFor(
        tester,
        MockQuestionnaireRemote(seeds: [seedFor(dass21Published())]),
        seedFor(dass21Published()),
      );
      await _walkWordForWord(tester, dass);
      // Wording is never trimmed: a published trailing space stays.
      final spaced = dass21Published();
      ((spaced['body']! as Map)['questions'] as List)[0]['text'] =
          'I found it hard to wind down ';
      expect(
        parsePublishedQuestionnaire(spaced).questions.first.text,
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
        expect(_familyOf(tester, 'Question 1 of 6'), contains('DMSans'));
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

  group('MOB3-35 sources: citation and attribution are shown', () {
    testWidgets('WHO-5 attribution on the first page and on Check answers', (
      tester,
    ) async {
      final seed = seedFor(who5Published());
      await pumpRunnerFor(tester, MockQuestionnaireRemote(seeds: [seed]), seed);
      const citation =
          'World Health Organization. The World Health Organization-Five '
          'Well-Being Index (WHO-5). Geneva: World Health Organization; 2024. '
          'License: CC-BY-NC-SA 3.0 IGO';
      const attribution = '© WHO, 2024. License: CC-BY-NC-SA 3.0 IGO';
      expect(find.text(citation), findsOneWidget);
      expect(find.text(attribution), findsOneWidget);
      for (final q in parsePublishedQuestionnaire(who5Published()).questions) {
        await answerAndNext(tester, q);
      }
      await tester.scrollUntilVisible(find.text(attribution), 200);
      expect(find.text(citation), findsOneWidget);
    });
  });

  group('MOB3-36 nothing for the psychologist ever reaches the screen', () {
    testWidgets(
      'category, validated, review warnings, scoring id: never shown',
      (tester) async {
        final seed = seedFor(allTypesWithHiddenFields());
        await pumpRunnerFor(
          tester,
          MockQuestionnaireRemote(seeds: [seed]),
          seed,
        );
        void noLeak() {
          for (final t in _texts(tester)) {
            for (final bad in [
              psychologistOnlyMarker,
              'fixed_instrument',
              'custom_psychologist',
              'cfg_secret',
              'validated',
              'warning',
            ]) {
              expect(t, isNot(contains(bad)), reason: t);
            }
          }
        }

        for (final q in en.questions) {
          noLeak();
          await answerAndNext(tester, q);
        }
        noLeak(); // Check answers page
      },
    );
  });

  group('MOB3-37 after submit: only "Response submitted" (+ time)', () {
    testWidgets('nothing else is shown or fetched', (tester) async {
      final r = MockQuestionnaireRemote();
      await pumpRunnerFor(tester, r, MockQuestionnaireRemote.demoSeeds()[2]);
      for (final q in parsePublishedQuestionnaire(demoRomanUrdu()).questions) {
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
        for (final q in parsePublishedQuestionnaire(
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

  group('MOB3-41 help text and the question picture', () {
    testWidgets('help_text under the question; picture with its description', (
      tester,
    ) async {
      await pumpRunnerFor(
        tester,
        MockQuestionnaireRemote(),
        MockQuestionnaireRemote.demoSeeds()[0],
      );
      for (final id in ['q_single']) {
        await answerAndNext(tester, en.question(id)!);
      }
      expect(find.byKey(const Key('question-help')), findsOneWidget);
      expect(find.text('Choose one or more.'), findsOneWidget);
      for (final id in [
        'q_multi',
        'q_yes_no',
        'q_likert',
        'q_free_text',
        'q_numeric',
      ]) {
        await answerAndNext(tester, en.question(id)!);
      }
      expect(find.byKey(const Key('question-picture')), findsOneWidget);
      expect(find.bySemanticsLabel('Green triangle'), findsOneWidget);
    });
    testWidgets('an unknown question picture shows its description text', (
      tester,
    ) async {
      final j = publishedFixture('pic', {
        'title': 'T',
        'language': 'en',
        'rtl': false,
        'questions': [
          {
            'question_id': 'q1',
            'type': 'single',
            'text': 'Look at the picture',
            'asset_id': 'not_bundled_01',
            'visual_description': 'A drawing of a tree',
            'options': [
              {'option_id': 'a', 'label': 'A'},
            ],
          },
        ],
      });
      final seed = seedFor(j);
      await pumpRunnerFor(tester, MockQuestionnaireRemote(seeds: [seed]), seed);
      expect(find.byKey(const Key('question-picture')), findsNothing);
      expect(find.text('A drawing of a tree'), findsOneWidget);
    });
  });

  group('MOB3-42 required multi needs at least one; yes_no keeps one', () {
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
      await tester.tap(find.byKey(const Key('q-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('option-o_yes')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('option-o_no')));
      await tester.pump();
      final yes = tester.getSemantics(find.byKey(const Key('option-o_yes')));
      final no = tester.getSemantics(find.byKey(const Key('option-o_no')));
      expect(yes.flagsCollection.isChecked, CheckedState.isFalse);
      expect(no.flagsCollection.isChecked, CheckedState.isTrue);
    });
  });
}
