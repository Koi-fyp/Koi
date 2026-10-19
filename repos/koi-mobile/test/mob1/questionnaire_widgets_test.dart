import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/questionnaires/asset_manifest.dart';
import 'package:koi_mobile/questionnaires/attempt_controller.dart';
import 'package:koi_mobile/questionnaires/mock_questionnaire_api.dart';
import 'package:koi_mobile/questionnaires/question_view.dart';
import 'package:koi_mobile/questionnaires/questionnaire_models.dart';
import 'package:koi_mobile/questionnaires/questionnaire_screens.dart';
import 'package:koi_mobile/theme/koi_text.dart';
import 'package:koi_mobile/widgets/koi_loader.dart';

import '../support/mob1_fakes.dart';
import '../support/real_fonts.dart';

final _versions = {
  for (final v in MockQuestionnaireRemote.demoVersions()) v.locale: v,
};

const _manifest = QuestionnaireAssetManifest(
  version: 'v0-placeholder',
  assets: {
    'placeholder.circle.v1': QuestionnaireAsset(
      path: 'assets/questionnaire_assets/placeholder_circle_v1.png',
      alt: {'en': 'Blue circle', 'ur': 'نیلا دائرہ', 'roman_ur': 'Neela daira'},
    ),
    'placeholder.square.v1': QuestionnaireAsset(
      path: 'assets/questionnaire_assets/placeholder_square_v1.png',
      alt: {'en': 'Yellow square'},
    ),
    'placeholder.triangle.v1': QuestionnaireAsset(
      path: 'assets/questionnaire_assets/placeholder_triangle_v1.png',
      alt: {'en': 'Green triangle'},
    ),
  },
);

Future<Answer?> _pumpQuestion(
  WidgetTester tester,
  Question q, {
  QuestionnaireLocale locale = QuestionnaireLocale.en,
  Answer? answer,
  QuestionnaireAssetManifest manifest = _manifest,
  String? manifestVersion = 'v0-placeholder',
  void Function(Answer)? onChanged,
}) async {
  Answer? last;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: QuestionView(
            question: q,
            locale: locale,
            answer: answer,
            manifest: manifest,
            manifestVersion: manifestVersion,
            onChanged: onChanged ?? (a) => last = a,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return last;
}

void main() {
  useRealFonts();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  final en = _versions[QuestionnaireLocale.en]!;
  Question q(String id) => en.question(id)!;

  group('MOB1-22 every question type renders and answers', () {
    testWidgets('single_choice / yes_no / likert choose one option', (
      tester,
    ) async {
      for (final id in ['q1', 'q3', 'q4']) {
        Answer? got;
        await _pumpQuestion(tester, q(id), onChanged: (a) => got = a);
        final option = q(id).options[1];
        await tester.tap(find.byKey(Key('option-${option.id}')));
        expect(got!.optionIds, [option.id], reason: id);
      }
    });
    testWidgets('multi_choice toggles several options', (tester) async {
      Answer? got;
      await _pumpQuestion(
        tester,
        q('q2'),
        answer: const Answer(optionIds: ['opt_A']),
        onChanged: (a) => got = a,
      );
      await tester.tap(find.byKey(const Key('option-opt_C')));
      expect(got!.optionIds, ['opt_A', 'opt_C']);
      await _pumpQuestion(
        tester,
        q('q2'),
        answer: const Answer(optionIds: ['opt_A', 'opt_C']),
        onChanged: (a) => got = a,
      );
      await tester.tap(find.byKey(const Key('option-opt_A')));
      expect(got!.optionIds, ['opt_C']);
    });
    testWidgets('short_text keeps within max length', (tester) async {
      Answer? got;
      await _pumpQuestion(tester, q('q5'), onChanged: (a) => got = a);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('short-text')),
          matching: find.byType(TextField),
        ),
        'x' * 250,
      );
      expect(got!.text!.length, 200);
    });
    testWidgets(
      'image_single / image_multi use bundled asset ids with alt labels',
      (tester) async {
        Answer? got;
        await _pumpQuestion(tester, q('q6'), onChanged: (a) => got = a);
        expect(find.byKey(const Key('image-img_circle')), findsOneWidget);
        expect(find.bySemanticsLabel('Blue circle'), findsOneWidget);
        await tester.tap(find.byKey(const Key('option-img_square')));
        expect(got!.optionIds, ['img_square']);
        await _pumpQuestion(tester, q('q7'), onChanged: (a) => got = a);
        await tester.tap(find.byKey(const Key('option-img_circle')));
        expect(got!.optionIds, ['img_circle']);
      },
    );
    testWidgets('choice tiles are at least 48dp tall', (tester) async {
      await _pumpQuestion(tester, q('q1'));
      expect(
        tester.getSize(find.byKey(const Key('option-opt_A'))).height,
        greaterThanOrEqualTo(48),
      );
    });
  });

  group('MOB1-23 Urdu RTL, Roman Urdu LTR, no new font family', () {
    testWidgets('Urdu question/answer block is RTL', (tester) async {
      final ur = _versions[QuestionnaireLocale.ur]!;
      await _pumpQuestion(
        tester,
        ur.question('q1')!,
        locale: QuestionnaireLocale.ur,
      );
      final dir = tester.widget<Directionality>(
        find
            .ancestor(
              of: find.byKey(const Key('question-q1')),
              matching: find.byType(Directionality),
            )
            .first,
      );
      expect(dir.textDirection, TextDirection.rtl);
      expect(find.text('نمونہ سوال 1'), findsOneWidget);
      // Option A sits to the RIGHT of the screen in RTL.
      final box = tester.getRect(find.byKey(const Key('option-opt_A')));
      final text = tester.getRect(find.text('اختیار A'));
      expect(text.right, greaterThan(box.center.dx));
    });
    testWidgets('Roman Urdu is LTR', (tester) async {
      final roman = _versions[QuestionnaireLocale.romanUr]!;
      await _pumpQuestion(
        tester,
        roman.question('q1')!,
        locale: QuestionnaireLocale.romanUr,
      );
      final dir = tester.widget<Directionality>(
        find
            .ancestor(
              of: find.byKey(const Key('question-q1')),
              matching: find.byType(Directionality),
            )
            .first,
      );
      expect(dir.textDirection, TextDirection.ltr);
      expect(find.text('Namoona sawal 1'), findsOneWidget);
    });
    test('Urdu text uses the theme family (system fallback for glyphs)', () {
      final style = questionnaireTextStyle(QuestionnaireLocale.ur);
      expect(style.fontFamily, KoiText.body().fontFamily);
      expect(
        style.fontFamilyFallback,
        KoiText.body().fontFamilyFallback,
        reason: 'no extra (Urdu) family added',
      );
      expect(style.height, greaterThan(1.5));
    });
  });

  group('MOB1-24 missing picture → accessible fallback, wording unchanged', () {
    testWidgets('unknown asset id shows the fallback with its label', (
      tester,
    ) async {
      await _pumpQuestion(tester, q('q7'));
      expect(
        find.byKey(const Key('image-fallback-img_missing')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Option D.*Picture unavailable')),
        findsOneWidget,
      );
      expect(find.text('Placeholder question 7'), findsOneWidget);
    });
    testWidgets('another manifest version → every picture falls back', (
      tester,
    ) async {
      await _pumpQuestion(tester, q('q6'), manifestVersion: 'v9');
      expect(
        find.byKey(const Key('image-fallback-img_circle')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('image-img_circle')), findsNothing);
    });
  });

  group('MOB1-25 missing translation → fallback, never other wording', () {
    testWidgets('no prompt in this locale shows the safe message', (
      tester,
    ) async {
      const missing = Question(
        id: 'qx',
        type: QuestionType.singleChoice,
        required: true,
        options: [ChoiceOption(id: 'a', label: 'A')],
      );
      await _pumpQuestion(tester, missing, locale: QuestionnaireLocale.ur);
      expect(find.byKey(const Key('question-missing-wording')), findsOneWidget);
      expect(find.text(missingWordingText), findsOneWidget);
      final v = QuestionnaireVersion(
        versionId: 'v',
        questionnaireId: 'q',
        locale: QuestionnaireLocale.ur,
        title: 't',
        questions: const [missing],
      );
      expect(
        missingRequired(v, const {
          'qx': Answer(optionIds: ['a']),
        }),
        ['qx'],
      );
    });
  });

  group('MOB1-34 runner: loaders, progress, validation, check answers, acknowledgement', () {
    testWidgets(
      'load → answer → check answers → submit → "Response submitted"',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final remote = MockQuestionnaireRemote(
          latency: const Duration(milliseconds: 100),
        );
        final h = Mob1Harness(
          user: AccountFakeAuth.registered('p1', 'p@x'),
          caps: {'p1': patientCaps},
          questionnaires: remote,
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: h.overrides,
            child: MaterialApp(
              home: Builder(
                builder: (context) => QuestionnaireRunnerScreen(
                  assignment: MockQuestionnaireRemote.demoAssignments().first,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        // Capabilities first (default-deny), then the questionnaire loader.
        await tester.pump(const Duration(milliseconds: 20));
        expect(find.byType(KoiLoader), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        expect(find.byType(KoiLoader), findsNothing);
        expect(find.bySemanticsLabel('Question 1 of 7'), findsOneWidget);

        // Next without an answer → validation on this question.
        await tester.tap(find.byKey(const Key('q-next')));
        await tester.pump();
        expect(find.text('Please answer this question.'), findsOneWidget);

        Future<void> choose(String option) async {
          await tester.ensureVisible(find.byKey(Key('option-$option')));
          await tester.tap(find.byKey(Key('option-$option')));
          await tester.pump();
          await tester.ensureVisible(find.byKey(const Key('q-next')));
          await tester.tap(find.byKey(const Key('q-next')));
          await tester.pumpAndSettle();
        }

        await choose('opt_A');
        await choose('opt_B');
        await choose('yes');
        await choose('l3');
        await tester.tap(find.byKey(const Key('q-next'))); // q5 optional
        await tester.pumpAndSettle();
        await choose('img_square');
        // q7 optional, last: Check answers.
        await tester.ensureVisible(find.byKey(const Key('q-previous')));
        await tester.tap(find.byKey(const Key('q-previous')));
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('Question 6 of 7'), findsOneWidget);
        await tester.tap(find.byKey(const Key('q-next')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('q-next')));
        await tester.pumpAndSettle();
        expect(find.text('Check your answers'), findsOneWidget);
        expect(find.text('Option A'), findsOneWidget);
        expect(find.text('Yellow square'), findsOneWidget);

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
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: SaveIndicator(status: SaveStatus.saving)),
          ),
        );
        expect(find.byType(KoiLoader), findsOneWidget);
        expect(find.bySemanticsLabel('Saving…'), findsOneWidget);
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: SaveIndicator(status: SaveStatus.saved)),
          ),
        );
        expect(find.byType(KoiLoader), findsNothing);
        expect(find.text('Saved'), findsOneWidget);
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: SaveIndicator(status: SaveStatus.offline)),
          ),
        );
        expect(find.text('Offline – not synced'), findsOneWidget);
      },
    );
  });
}
