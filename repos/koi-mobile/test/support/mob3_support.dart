import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/questionnaires/asset_manifest.dart';
import 'package:koi_mobile/questionnaires/mock_fixtures.dart';
import 'package:koi_mobile/questionnaires/mock_questionnaire_api.dart';
import 'package:koi_mobile/questionnaires/questionnaire_models.dart';
import 'package:koi_mobile/questionnaires/questionnaire_providers.dart';
import 'package:koi_mobile/questionnaires/questionnaire_screens.dart';
import 'package:koi_mobile/settings/settings_prefs.dart';

import 'mob1_fakes.dart';

/// The AI track's QuestionnaireDraft template (test fixture only).
Map<String, Object?> templateFixture(String name) => (jsonDecode(
  File('test/fixtures/mob3/${name}_template.json').readAsStringSync(),
) as Map).cast<String, Object?>();

/// Wraps a QuestionnaireDraft body as Web would publish it.
Map<String, Object?> publishedFixture(
  String questionnaireId,
  Map<String, Object?> body, {
  String status = 'published',
}) => {
  'questionnaire_id': questionnaireId,
  'version': 1,
  'org_id': 'org_test',
  'status': status,
  'body': body,
};

Map<String, Object?> who5Published() =>
    publishedFixture('who5', templateFixture('who5_en'));

Map<String, Object?> dass21Published() =>
    publishedFixture('dass21', templateFixture('dass21_en'));

/// Distinctive text that must never reach the patient screen.
const String psychologistOnlyMarker = 'PSYCHOLOGIST ONLY MARKER';

/// The English all-types fixture plus every field a patient must never
/// see or keep: scoring config id, category, validated, review warnings
/// and evaluation-like fields at every level.
Map<String, Object?> allTypesWithHiddenFields() {
  final j = demoAllTypesEn();
  final body = (j['body']! as Map).cast<String, Object?>();
  return {
    ...j,
    'scoring_config_id': 'cfg_secret',
    'interpretation': '$psychologistOnlyMarker interpretation',
    'body': {
      ...body,
      'category': 'fixed_instrument',
      'validated': true,
      'review_warnings': [
        {
          'code': 'demo_note',
          'severity': 'warning',
          'message': '$psychologistOnlyMarker review warning',
          'question_id': 'q_single',
        },
      ],
      'score': 99,
      'band': '$psychologistOnlyMarker band',
      'questions': [
        for (final q in (body['questions']! as List).cast<Map>())
          {
            ...q.cast<String, Object?>(),
            'weight': 3,
            'reverse_scored': true,
            'options': [
              for (final o in (q['options']! as List).cast<Map>())
                {...o.cast<String, Object?>(), 'value': 5, 'score': 5},
            ],
          },
      ],
    },
  };
}

MockAssignmentSeed seedFor(
  Map<String, Object?> published, {
  String id = 'test',
  Map<String, String> title = const {'en': 'Test form'},
}) => MockAssignmentSeed(
  assignmentId: '${id}_assignment',
  attemptId: '${id}_attempt',
  versionId: '${id}_version',
  title: title,
  questionnaire: published,
);

Assignment assignmentOf(MockAssignmentSeed s) => Assignment(
  assignmentId: s.assignmentId,
  attemptId: s.attemptId,
  versionId: s.versionId,
  title: s.title,
  state: AssignmentState.assigned,
);

/// The bundled manifest, read synchronously from disk: rootBundle loads are
/// real async I/O that does not reliably finish inside testWidgets.
QuestionnaireAssetManifest bundledManifest() =>
    QuestionnaireAssetManifest.fromJson(
      jsonDecode(
        File(QuestionnaireAssetManifest.manifestPath).readAsStringSync(),
      ),
    );

/// Pumps the runner for [seed] on a 360 x 800 dp phone. Returns the harness.
Future<Mob1Harness> pumpRunnerFor(
  WidgetTester tester,
  MockQuestionnaireRemote remote,
  MockAssignmentSeed seed, {
  String? settingsLanguage,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final h = Mob1Harness(
    user: AccountFakeAuth.registered('p1', 'p@x'),
    caps: {'p1': patientCaps},
    questionnaires: remote,
  );
  if (settingsLanguage != null) {
    h.settings.values['p1'] = SettingsPrefs(language: settingsLanguage);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...h.overrides,
        questionnaireAssetManifestProvider.overrideWith(
          (ref) => Future.value(bundledManifest()),
        ),
      ],
      child: MaterialApp(
        home: QuestionnaireRunnerScreen(assignment: assignmentOf(seed)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  await tester.pumpAndSettle();
  return h;
}

/// Answers the visible question (first option / its minimum / "x") when
/// required, then taps Next (or Check answers on the last one).
Future<void> answerAndNext(WidgetTester tester, Question q) async {
  if (q.required) {
    switch (q.type) {
      case QuestionType.freeText:
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('free-text')),
            matching: find.byType(TextField),
          ),
          'x',
        );
      case QuestionType.numeric:
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('numeric-input')),
            matching: find.byType(TextField),
          ),
          '${(q.minValue ?? 0).toInt()}',
        );
      default:
        final option = find.byKey(Key('option-${q.options.first.id}'));
        await tester.ensureVisible(option);
        await tester.tap(option);
    }
    await tester.pump();
  }
  await tester.ensureVisible(find.byKey(const Key('q-next')));
  await tester.tap(find.byKey(const Key('q-next')));
  await tester.pumpAndSettle();
}

/// Code only: `//` comments stripped.
String codeOf(File f) => f
    .readAsLinesSync()
    .map((l) {
      final i = l.indexOf('//');
      return i < 0 ? l : l.substring(0, i);
    })
    .join('\n');

Iterable<File> dartFilesUnder(String dir) =>
    Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
