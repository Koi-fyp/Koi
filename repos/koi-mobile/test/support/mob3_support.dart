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

/// MOB-6: an AI-track instrument template converted to the contract
/// v0.5.2 `PatientQuestionnaireDTO` (English only), wording and option
/// order unchanged. The template's description, sources and AI keys have
/// no place in v0.5.2 and are left out.
Map<String, Object?> instrumentQuestionnaire(String name) {
  final t = templateFixture(name);
  Map<String, Object?> en(Object? text) => {'en': text};
  return {
    'version_id': 'test_version',
    'schema_version': '0.5.0',
    'title': en(t['title']),
    'locales': const ['en'],
    'questions': [
      for (final q in (t['questions']! as List).cast<Map>())
        {
          'id': q['question_id'],
          'type': q['type'],
          'prompt': en(q['text']),
          'required': q['required'] ?? true,
          'options': [
            for (final o in (q['options']! as List).cast<Map>())
              {'id': o['option_id'], 'label': en(o['label'])},
          ],
        },
    ],
  };
}

Map<String, Object?> who5Published() => instrumentQuestionnaire('who5_en');

Map<String, Object?> dass21Published() => instrumentQuestionnaire('dass21_en');

/// Distinctive text that must never reach the patient screen.
const String psychologistOnlyMarker = 'PSYCHOLOGIST ONLY MARKER';

/// The all-types fixture plus fields a patient must never see or keep
/// (scores, evaluation, review, job state) at every level. Contract v0.5.2
/// forbids extra keys, so the app REFUSES this questionnaire (MOB-6).
Map<String, Object?> allTypesWithHiddenFields() {
  final j = demoAllTypesEn();
  return {
    ...j,
    'scoring_version': 'cfg_secret',
    'interpretation': '$psychologistOnlyMarker interpretation',
    'questions': [
      for (final q in (j['questions']! as List).cast<Map>())
        {...q.cast<String, Object?>(), 'weight': 3, 'reverse_scored': true},
    ],
  };
}

/// [questionnaire] with one key added at [path] (`questions.0.options.1`
/// style), for the strictness tests.
Map<String, Object?> withExtraKey(
  Map<String, Object?> questionnaire,
  List<Object> path, [
  String key = 'score',
  Object value = 5,
]) {
  Object? copy(Object? v) => switch (v) {
    final Map m => {for (final e in m.entries) e.key as String: copy(e.value)},
    final List l => [for (final x in l) copy(x)],
    _ => v,
  };
  final out = copy(questionnaire)! as Map<String, Object?>;
  Object? node = out;
  for (final p in path) {
    node = p is int ? (node! as List)[p] : (node! as Map)[p];
  }
  (node! as Map)[key] = value;
  return out;
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
  // The questionnaire is the version the assignment is pinned to.
  questionnaire: {...published, 'version_id': '${id}_version'},
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

/// Pumps the runner for [seed] on a [widthDp] x 800 dp phone (360 by
/// default). Returns the harness.
Future<Mob1Harness> pumpRunnerFor(
  WidgetTester tester,
  MockQuestionnaireRemote remote,
  MockAssignmentSeed seed, {
  String? settingsLanguage,
  double widthDp = 360,
}) async {
  tester.view.physicalSize = Size(widthDp * 3, 2400);
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

/// Answers the visible question (first option(s) up to its minimum /
/// "yes" / "x") when required, then taps Next (or Check answers on the
/// last one).
Future<void> answerAndNext(WidgetTester tester, Question q) async {
  if (q.required) {
    switch (q.type) {
      case QuestionType.shortText:
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('free-text')),
            matching: find.byType(TextField),
          ),
          'x',
        );
      case QuestionType.yesNo:
        await tester.ensureVisible(find.byKey(const Key('option-yes')));
        await tester.tap(find.byKey(const Key('option-yes')));
      default:
        final n = q.type.isMulti && q.minSelections > 1 ? q.minSelections : 1;
        for (final o in q.options.take(n)) {
          final option = find.byKey(Key('option-${o.id}'));
          await tester.ensureVisible(option);
          await tester.tap(option);
          await tester.pump();
        }
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
