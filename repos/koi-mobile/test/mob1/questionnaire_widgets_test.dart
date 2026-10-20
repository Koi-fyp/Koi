import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/care/care_strings.dart';
import 'package:koi_mobile/questionnaires/asset_manifest.dart';
import 'package:koi_mobile/questionnaires/attempt_controller.dart';
import 'package:koi_mobile/questionnaires/mock_fixtures.dart';
import 'package:koi_mobile/questionnaires/mock_questionnaire_api.dart';
import 'package:koi_mobile/questionnaires/question_view.dart';
import 'package:koi_mobile/questionnaires/questionnaire_models.dart';
import 'package:koi_mobile/questionnaires/questionnaire_screens.dart';
import 'package:koi_mobile/questionnaires/questionnaire_wire.dart';
import 'package:koi_mobile/theme/koi_text.dart';
import 'package:koi_mobile/widgets/koi_loader.dart';

import '../support/mob1_fakes.dart';
import '../support/real_fonts.dart';

// MOB-3 rewrite: same MOB-1 IDs, now rendering the AI QuestionnaireDraft
// body (PROVISIONAL) with the MOB-2 string table.

final _en = parsePublishedQuestionnaire(demoAllTypesEn());

const _manifest = QuestionnaireAssetManifest(
  assets: {
    'placeholder_circle_v1': QuestionnaireAsset(
      assetId: 'placeholder_circle_v1',
      kind: 'placeholder',
      visualDescription: 'Blue circle',
    ),
    'placeholder_square_v1': QuestionnaireAsset(
      assetId: 'placeholder_square_v1',
      kind: 'placeholder',
      visualDescription: 'Yellow square',
    ),
    'placeholder_triangle_v1': QuestionnaireAsset(
      assetId: 'placeholder_triangle_v1',
      kind: 'placeholder',
      visualDescription: 'Green triangle',
    ),
  },
);

Future<void> _pumpQuestion(
  WidgetTester tester,
  Question q, {
  QuestionnaireLanguage language = QuestionnaireLanguage.en,
  Answer? answer,
  QuestionnaireAssetManifest manifest = _manifest,
  void Function(AnswerValue)? onChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: QuestionView(
            question: q,
            language: language,
            answer: answer,
            manifest: manifest,
            strings: CareStrings.en,
            onChanged: onChanged ?? (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The runner for one demo assignment, on a 360dp phone.
Future<MockQuestionnaireRemote> _pumpRunner(
  WidgetTester tester, {
  int assignment = 0,
  Duration latency = Duration.zero,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final remote = MockQuestionnaireRemote(latency: latency);
  final seed = MockQuestionnaireRemote.demoSeeds()[assignment];
  final h = Mob1Harness(
    user: AccountFakeAuth.registered('p1', 'p@x'),
    caps: {'p1': patientCaps},
    questionnaires: remote,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: h.overrides,
      child: MaterialApp(
        home: QuestionnaireRunnerScreen(
          assignment: Assignment(
            assignmentId: seed.assignmentId,
            attemptId: seed.attemptId,
            versionId: seed.versionId,
            title: seed.title,
            state: AssignmentState.assigned,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  return remote;
}

void main() {
  useRealFonts();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  Question q(String id) => _en.question(id)!;

  group('MOB1-22 every question type renders and answers', () {
    testWidgets('single / yes_no / likert choose one option', (tester) async {
      for (final id in ['q_single', 'q_yes_no', 'q_likert']) {
        AnswerValue? got;
        await _pumpQuestion(tester, q(id), onChanged: (a) => got = a);
        final option = q(id).options[1];
        await tester.tap(find.byKey(Key('option-${option.id}')));
        expect(got!.optionIds, [option.id], reason: id);
      }
    });
    testWidgets('multi toggles several options', (tester) async {
      AnswerValue? got;
      await _pumpQuestion(
        tester,
        q('q_multi'),
        answer: const Answer(
          answerId: 'a1',
          questionId: 'q_multi',
          optionIds: ['o_a'],
        ),
        onChanged: (a) => got = a,
      );
      await tester.tap(find.byKey(const Key('option-o_c')));
      expect(got!.optionIds, ['o_a', 'o_c']);
      await _pumpQuestion(
        tester,
        q('q_multi'),
        answer: const Answer(
          answerId: 'a1',
          questionId: 'q_multi',
          optionIds: ['o_a', 'o_c'],
        ),
        onChanged: (a) => got = a,
      );
      await tester.tap(find.byKey(const Key('option-o_a')));
      expect(got!.optionIds, ['o_c']);
    });
    testWidgets('free_text keeps within 4000 characters', (tester) async {
      AnswerValue? got;
      await _pumpQuestion(tester, q('q_free_text'), onChanged: (a) => got = a);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('free-text')),
          matching: find.byType(TextField),
        ),
        'x' * 4100,
      );
      expect(got!.text!.length, 4000);
    });
    testWidgets(
      'image_single / image_multi use bundled asset ids with their descriptions',
      (tester) async {
        AnswerValue? got;
        await _pumpQuestion(
          tester,
          q('q_image_single'),
          onChanged: (a) => got = a,
        );
        expect(find.byKey(const Key('image-img_circle')), findsOneWidget);
        expect(find.bySemanticsLabel('Circle. Blue circle'), findsOneWidget);
        await tester.tap(find.byKey(const Key('option-img_square')));
        expect(got!.optionIds, ['img_square']);
        await _pumpQuestion(
          tester,
          q('q_image_multi'),
          onChanged: (a) => got = a,
        );
        await tester.tap(find.byKey(const Key('option-img_circle')));
        expect(got!.optionIds, ['img_circle']);
      },
    );
    testWidgets('choice tiles are at least 48dp tall', (tester) async {
      await _pumpQuestion(tester, q('q_single'));
      expect(
        tester.getSize(find.byKey(const Key('option-o_a'))).height,
        greaterThanOrEqualTo(48),
      );
    });
  });

  group('MOB1-23 Urdu RTL, Roman Urdu LTR, Nastaliq for Urdu wording only', () {
    TextDirection directionOf(WidgetTester tester, String questionId) => tester
        .widget<Directionality>(
          find
              .ancestor(
                of: find.byKey(Key('question-$questionId')),
                matching: find.byType(Directionality),
              )
              .first,
        )
        .textDirection;

    testWidgets('an Urdu (rtl) questionnaire is laid out right-to-left', (
      tester,
    ) async {
      await _pumpRunner(tester, assignment: 1);
      await tester.pumpAndSettle();
      expect(directionOf(tester, 'q_single'), TextDirection.rtl);
      expect(find.text('نمونہ سوال ایک'), findsOneWidget);
      // Option text sits on the RIGHT of its tile in RTL.
      final box = tester.getRect(find.byKey(const Key('option-o_a')));
      final text = tester.getRect(find.text('اختیار الف'));
      expect(text.right, greaterThan(box.center.dx));
    });
    testWidgets('a Roman Urdu questionnaire is left-to-right', (tester) async {
      await _pumpRunner(tester, assignment: 2);
      await tester.pumpAndSettle();
      expect(directionOf(tester, 'q_single'), TextDirection.ltr);
      expect(find.text('Namoona sawal ek'), findsOneWidget);
    });
    test('Urdu wording uses Noto Nastaliq Urdu; English and Roman Urdu keep '
        'the theme family', () {
      final ur = questionnaireTextStyle(QuestionnaireLanguage.ur);
      expect(ur.fontFamily, KoiText.urduQuestionnaire().fontFamily);
      expect(ur.fontFamily, isNot(KoiText.body().fontFamily));
      for (final l in [
        QuestionnaireLanguage.en,
        QuestionnaireLanguage.romanUr,
      ]) {
        expect(
          questionnaireTextStyle(l).fontFamily,
          KoiText.body().fontFamily,
          reason: l.name,
        );
      }
    });
  });

  group('MOB1-24 missing picture → its description, wording unchanged', () {
    testWidgets('unknown asset id / no asset id show the visual description', (
      tester,
    ) async {
      await _pumpQuestion(tester, q('q_image_multi'));
      expect(
        find.byKey(const Key('image-fallback-img_missing')),
        findsOneWidget,
      );
      expect(find.text('A five-pointed star'), findsOneWidget);
      expect(find.text('A crescent moon'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Star. A five-pointed star'),
        findsOneWidget,
      );
      expect(find.text('Placeholder pictures (choose any)'), findsOneWidget);
    });
    testWidgets('no manifest → every picture falls back to text', (
      tester,
    ) async {
      await _pumpQuestion(
        tester,
        q('q_image_single'),
        manifest: QuestionnaireAssetManifest.empty,
      );
      expect(
        find.byKey(const Key('image-fallback-img_circle')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('image-img_circle')), findsNothing);
      expect(find.text('Picture unavailable'), findsNWidgets(3));
    });
  });

  group('MOB1-25 missing wording → refused, never other wording', () {
    test(
      'an empty question text or option label refuses the questionnaire',
      () {
        Map<String, Object?> withText(String text, String label) => {
          'questionnaire_id': 'q',
          'version': 1,
          'status': 'published',
          'body': {
            'title': 'T',
            'language': 'ur',
            'rtl': true,
            'questions': [
              {
                'question_id': 'q1',
                'type': 'single',
                'text': text,
                'options': [
                  {'option_id': 'a', 'label': label},
                ],
              },
            ],
          },
        };
        expect(
          () => parsePublishedQuestionnaire(withText('', 'A')),
          throwsFormatException,
        );
        expect(
          () => parsePublishedQuestionnaire(withText('سوال', '')),
          throwsFormatException,
        );
        expect(
          parsePublishedQuestionnaire(withText('سوال', 'A'))
              .questions
              .single
              .text,
          'سوال',
        );
      },
    );
  });

  group('MOB1-34 runner: loaders, progress, validation, check answers, acknowledgement', () {
    testWidgets(
      'load → answer → check answers → submit → "Response submitted"',
      (tester) async {
        final remote = await _pumpRunner(
          tester,
          latency: const Duration(milliseconds: 100),
        );
        expect(find.byType(KoiLoader), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        expect(find.byType(KoiLoader), findsNothing);
        expect(find.bySemanticsLabel('Question 1 of 8'), findsOneWidget);

        // Next without an answer → validation on this question.
        await tester.tap(find.byKey(const Key('q-next')));
        await tester.pump();
        expect(find.text('Please answer this question.'), findsOneWidget);

        Future<void> next() async {
          await tester.ensureVisible(find.byKey(const Key('q-next')));
          await tester.tap(find.byKey(const Key('q-next')));
          await tester.pumpAndSettle();
        }

        Future<void> choose(String option) async {
          await tester.ensureVisible(find.byKey(Key('option-$option')));
          await tester.tap(find.byKey(Key('option-$option')));
          await tester.pump();
          await next();
        }

        await choose('o_a');
        await choose('o_b');
        await choose('o_yes');
        await choose('o3');
        await next(); // free text is optional
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('numeric-input')),
            matching: find.byType(TextField),
          ),
          '4',
        );
        await tester.pump();
        await next();
        await choose('img_square');
        // Image multi is optional and last: Check answers.
        await tester.ensureVisible(find.byKey(const Key('q-previous')));
        await tester.tap(find.byKey(const Key('q-previous')));
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('Question 7 of 8'), findsOneWidget);
        await next();
        await next();
        expect(find.text('Check your answers'), findsOneWidget);
        expect(find.text('Option A'), findsOneWidget);
        expect(find.text('Square'), findsOneWidget);
        expect(find.text('4'), findsOneWidget);

        await tester.ensureVisible(find.byKey(const Key('q-submit')));
        await tester.tap(find.byKey(const Key('q-submit')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        expect(find.bySemanticsLabel('Submitting…'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();
        expect(find.byType(KoiLoader), findsNothing);
        // MOB1-37: only "Response submitted" (+ time).
        expect(find.text(AcknowledgementView.title), findsOneWidget);
        expect(find.byKey(const Key('ack-time')), findsOneWidget);
        for (final word in [
          'score',
          'result',
          'evaluation',
          'review',
          'pending',
        ]) {
          expect(
            find.textContaining(RegExp(word, caseSensitive: false)),
            findsNothing,
            reason: word,
          );
        }
        expect(remote.committedSubmissions, 1);
      },
    );

    testWidgets(
      'autosave shows the KoiLoader "Saving…" indicator, then "Saved"',
      (tester) async {
        Future<void> show(SaveStatus s) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: SaveIndicator(status: s)),
          ),
        );
        await show(SaveStatus.saving);
        expect(find.byType(KoiLoader), findsOneWidget);
        expect(find.bySemanticsLabel('Saving…'), findsOneWidget);
        await show(SaveStatus.saved);
        expect(find.byType(KoiLoader), findsNothing);
        expect(find.text('Saved'), findsOneWidget);
        await show(SaveStatus.offline);
        expect(find.text('Offline – not synced'), findsOneWidget);
        await show(SaveStatus.notSaved);
        expect(find.text('Not saved'), findsOneWidget);
      },
    );
  });
}
