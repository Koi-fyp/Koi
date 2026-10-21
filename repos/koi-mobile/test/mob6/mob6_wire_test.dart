import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/core/crypto_context.dart';
import 'package:koi_mobile/questionnaires/asset_manifest.dart';
import 'package:koi_mobile/questionnaires/attempt_controller.dart';
import 'package:koi_mobile/questionnaires/draft_store.dart';
import 'package:koi_mobile/questionnaires/mock_fixtures.dart';
import 'package:koi_mobile/questionnaires/mock_questionnaire_api.dart';
import 'package:koi_mobile/questionnaires/questionnaire_models.dart';
import 'package:koi_mobile/questionnaires/questionnaire_wire.dart';

import '../support/mob1_fakes.dart';
import '../support/mob3_support.dart';

/// The contract's own example file (test/fixtures/mob6/README.md).
final Map<String, Object?> _fixtures = (jsonDecode(
  File('test/fixtures/mob6/contracts_v0.5.2_fixtures.json').readAsStringSync(),
) as Map).cast<String, Object?>();

Object? _fixture(String group, String name) => ((_fixtures[group]! as List)
    .cast<Map>()
    .singleWhere((f) => f['name'] == name))['value'];

Matcher get _refused => throwsA(
  anyOf(isA<UnsupportedQuestionnaireException>(), isA<FormatException>()),
);

/// [question] inside an otherwise valid questionnaire.
Map<String, Object?> _withQuestion(Object? question) => {
  'version_id': 'v1',
  'schema_version': '0.5.0',
  'title': {'en': 'T'},
  'locales': ['en'],
  'questions': [question],
};

Question _q(Map<String, Object?> j) =>
    parsePatientQuestionnaire(_withQuestion(j)).questions.single;

Question _multi({int min = 0, int max = 3, bool required = true}) => _q({
  'id': 'm',
  'type': 'multi_choice',
  'prompt': {'en': 'M'},
  'required': required,
  'min_selections': min,
  'max_selections': max,
  'options': [
    for (final id in ['a', 'b', 'c', 'd'])
      {
        'id': id,
        'label': {'en': id},
      },
  ],
});

Question _text({int max = 10, bool required = true}) => _q({
  'id': 't',
  'type': 'short_text',
  'prompt': {'en': 'T'},
  'required': required,
  'max_length': max,
});

Answer _m(List<String> ids) =>
    Answer(questionId: 'm', type: QuestionType.multi, value: ids);

Answer _t(String text) =>
    Answer(questionId: 't', type: QuestionType.shortText, value: text);

void main() {
  group('MOB6-01 fixtures.json: every valid patient case parses', () {
    test('in-progress detail (patient_detail)', () {
      final d = parseAssignmentDetail(
        _fixture('valid', 'patient_detail'),
      ) as OpenAssignment;
      expect(d.assignment.assignmentId, 'assignment_1');
      expect(d.questionnaire.versionId, 'version_1');
      expect(d.questionnaire.locales, [
        QuestionnaireLanguage.en,
        QuestionnaireLanguage.ur,
      ]);
      expect(d.questionnaire.questions.map((q) => q.type), [
        QuestionType.single,
        QuestionType.yesNo,
      ]);
      expect(d.attempt.revision, 1);
      expect(
        d.attempt.answers.single,
        const Answer(
          questionId: 'q_1',
          type: QuestionType.single,
          value: 'option_1',
        ),
      );
    });
    test('submitted detail and the submit acknowledgement', () {
      final d = parseAssignmentDetail(
        _fixture('valid', 'submitted_detail'),
      ) as SubmittedAssignment;
      expect(d.acknowledgement.attemptId, 'attempt_1');
      final ack = parseSubmitAck(_fixture('valid', 'submit_ack'));
      expect(ack.submittedAt, DateTime.utc(2026, 10, 19, 12));
    });
    test('the AutosaveRequest example round-trips byte for byte', () {
      final raw = _fixture('valid', 'autosave')! as Map<String, Object?>;
      final answers = [
        for (final a in raw['answers']! as List) decodeAnswer(a),
      ];
      expect(
        jsonEncode(encodeAutosave(raw['expected_revision']! as int, answers)),
        jsonEncode(raw),
      );
    });
  });

  group('MOB6-02 fixtures.json: every invalid patient case is refused', () {
    test('score / job / evaluation leaks', () {
      expect(
        () => parseSubmitAck(_fixture('invalid', 'ack_score_leak')),
        _refused,
      );
      expect(
        () => parseSubmitAck(_fixture('invalid', 'ack_job_leak')),
        _refused,
      );
      expect(
        () =>
            parseAssignment(_fixture('invalid', 'assignment_evaluation_leak')),
        _refused,
      );
      expect(
        () => parseAttempt(_fixture('invalid', 'attempt_score_leak')),
        _refused,
      );
    });
    test('submitted answers and a submitted detail with its answers', () {
      expect(
        () => parseAttempt(
          _fixture('invalid', 'submitted_answers_feature_disabled'),
        ),
        _refused,
      );
      expect(
        () => parseAssignmentDetail(
          _fixture(
            'invalid',
            'submitted_detail_cannot_include_original_answers',
          ),
        ),
        _refused,
      );
    });
    test('external image URL and the numeric type', () {
      for (final name in ['external_image_url', 'numeric_not_supported']) {
        expect(
          () => parsePatientQuestionnaire(
            _withQuestion(_fixture('invalid', name)),
          ),
          _refused,
          reason: name,
        );
      }
    });
    test(
      'identity forgery (patient_uid in the body): the app never sends it',
      () {
        final forged =
            _fixture('invalid', 'attempt_identity_forgery')!
                as Map<String, Object?>;
        expect(forged.keys, contains('patient_uid'));
        expect(encodeAutosave(1, const []).keys.toSet(), {
          'expected_revision',
          'answers',
        });
      },
    );
  });

  group('MOB6-03 every encoder writes exactly the contract keys', () {
    test('one Answer per type; AutosaveRequest; PatientSubmitRequest', () {
      final samples = <QuestionType, Object>{
        QuestionType.single: 'o1',
        QuestionType.multi: const ['o1', 'o2'],
        QuestionType.yesNo: true,
        QuestionType.likert: 'o3',
        QuestionType.shortText: 'words',
        QuestionType.imageSingle: 'img1',
        QuestionType.imageMulti: const <String>[],
      };
      expect(samples.keys.toSet(), QuestionType.values.toSet());
      for (final e in samples.entries) {
        final a = Answer(questionId: 'q1', type: e.key, value: e.value);
        final j = encodeAnswer(a);
        expect(j.keys.toList(), ['question_id', 'type', 'value']);
        expect(j['type'], e.key.wire);
        expect(decodeAnswer(jsonDecode(jsonEncode(j))), a, reason: e.key.wire);
      }
      expect(encodeSubmit(4), {'expected_revision': 4});
      expect(
        jsonEncode(encodeAutosave(2, const [])),
        '{"expected_revision":2,"answers":[]}',
      );
    });
  });

  group('MOB6-04 answerIssues mirrors answers.ts rule for rule', () {
    final m = _multi(min: 2, max: 3);
    final t = _text(max: 5);
    final yes = _q({
      'id': 'y',
      'type': 'yes_no',
      'prompt': {'en': 'Y'},
      'required': true,
    });
    final questions = [m, t, yes];
    final cases = <String, (List<Answer>, bool, bool)>{
      // name: (answers, isFinal, accepted)
      'empty save': (const [], false, true),
      'empty submit': (const [], true, false),
      'empty multi in a save': ([_m(const [])], false, true),
      'multi below min in a save': (
        [
          _m(const ['a']),
        ],
        false,
        false,
      ),
      'multi at min': (
        [
          _m(const ['a', 'b']),
        ],
        false,
        true,
      ),
      'multi above max': (
        [
          _m(const ['a', 'b', 'c', 'd']),
        ],
        false,
        false,
      ),
      'multi duplicate': (
        [
          _m(const ['a', 'a']),
        ],
        false,
        false,
      ),
      'multi unknown option': (
        [
          _m(const ['a', 'z']),
        ],
        false,
        false,
      ),
      'text at max_length': ([_t('12345')], false, true),
      'text above max_length': ([_t('123456')], false, false),
      'blank required text in a save': ([_t('   ')], false, true),
      'blank required text on submit': (
        [
          _m(const ['a', 'b']),
          _t('   '),
          const Answer(questionId: 'y', type: QuestionType.yesNo, value: true),
        ],
        true,
        false,
      ),
      'complete submit': (
        [
          _m(const ['a', 'b']),
          _t('x'),
          const Answer(questionId: 'y', type: QuestionType.yesNo, value: false),
        ],
        true,
        true,
      ),
      'type mismatch': (
        [const Answer(questionId: 'y', type: QuestionType.single, value: 'a')],
        false,
        false,
      ),
      'duplicate answer': ([_t('a'), _t('b')], false, false),
      'unknown question': (
        [const Answer(questionId: 'z', type: QuestionType.yesNo, value: true)],
        false,
        false,
      ),
    };
    for (final e in cases.entries) {
      test(e.key, () {
        final (answers, isFinal, ok) = e.value;
        expect(answerIssues(questions, answers, isFinal: isFinal).isEmpty, ok);
      });
    }
  });

  group('MOB6-05 the app sends only what the server accepts', () {
    test('a below-minimum selection stays local; submit lists it', () {
      final m = _multi(min: 2, max: 3, required: false);
      final q = PublishedQuestionnaire(
        versionId: 'v',
        title: const LocalizedText({QuestionnaireLanguage.en: 'T'}),
        locales: const [QuestionnaireLanguage.en],
        questions: [m],
      );
      final below = {
        'm': _m(const ['a']),
      };
      expect(sanitizeAnswers(q, below), hasLength(1), reason: 'kept locally');
      expect(sendableAnswers(q, below), isEmpty, reason: 'never sent');
      expect(isBelowMinimum(m, below['m']), isTrue);
      expect(missingRequired(q, below), ['m'], reason: 'blocks submit');
      expect(missingRequired(q, const {}), isEmpty, reason: 'optional');
      final ok = {
        'm': _m(const ['a', 'b']),
      };
      expect(sendableAnswers(q, ok), [ok['m']]);
      expect(answerIssues(q.questions, sendableAnswers(q, below)), isEmpty);
    });
    test('required: text not blank, multi at least max(1, min)', () {
      expect(questionComplete(_text(), _t('  ')), isFalse);
      expect(questionComplete(_text(), _t(' x ')), isTrue);
      expect(questionComplete(_text(required: false), null), isTrue);
      expect(questionComplete(_multi(min: 0), _m(const ['a'])), isTrue);
      expect(questionComplete(_multi(min: 0), null), isFalse);
      expect(questionComplete(_multi(min: 3), _m(const ['a', 'b'])), isFalse);
    });
  });

  group('MOB6-06 which language is shown', () {
    final all = parsePatientQuestionnaire(demoAllTypesEn());
    final roman = parsePatientQuestionnaire(demoRomanUrdu());
    test('app language → English → first published locale', () {
      expect(all.defaultLanguage('ur'), QuestionnaireLanguage.ur);
      expect(all.defaultLanguage('en'), QuestionnaireLanguage.en);
      expect(roman.defaultLanguage('en'), QuestionnaireLanguage.romanUr);
      expect(
        parsePatientQuestionnaire(demoUrdu()).defaultLanguage('en'),
        QuestionnaireLanguage.ur,
      );
    });
    test('wording per locale; yes / no as on the web', () {
      expect(all.title.resolve(QuestionnaireLanguage.romanUr), 'Namoona form');
      expect(all.title.resolve(QuestionnaireLanguage.ur), 'نمونہ فارم');
      expect(
        [for (final l in QuestionnaireLanguage.values) (l.yes, l.no)],
        [('Yes', 'No'), ('ہاں', 'نہیں'), ('Haan', 'Nahin')],
      );
      expect(
        [for (final l in QuestionnaireLanguage.values) l.wire],
        ['en', 'ur', 'ur-Latn'],
      );
    });
  });

  group('MOB6-07 no sources / description / help text in v0.5.2', () {
    test('those keys are refused, at the questionnaire and question level', () {
      final base = demoAllTypesEn();
      for (final (path, key) in <(List<Object>, String)>[
        (const [], 'sources'),
        (const [], 'description'),
        (const ['questions', 0], 'help_text'),
        (const ['questions', 0], 'visual_description'),
        (const ['questions', 0], 'asset_id'),
        (const ['questions', 0, 'options', 0], 'value'),
      ]) {
        expect(
          () => parsePatientQuestionnaire(withExtraKey(base, path, key, 'x')),
          _refused,
          reason: '$path.$key',
        );
      }
      expect(() => parsePatientQuestionnaire(base), returnsNormally);
    });
  });

  group('MOB6-08 bundled pictures are pinned by asset_id, version, sha256', () {
    test('every pinned hash matches its file on disk', () async {
      for (final ref in QuestionnaireAssetManifest.bundledReferences.values) {
        final bytes = File('assets/questionnaire/${ref.assetId}.png')
            .readAsBytesSync();
        final hash = await Sha256().hash(bytes);
        final hex = [
          for (final b in hash.bytes) b.toRadixString(16).padLeft(2, '0'),
        ].join();
        expect(hex, ref.sha256, reason: ref.assetId);
        expect(ref.version, 1);
      }
    });
    test('a picture resolves only when all three fields match', () {
      final m = bundledManifest();
      final pinned = QuestionnaireAssetManifest
          .bundledReferences['placeholder_circle_v1']!;
      expect(m.resolveReference(pinned)!.assetId, 'placeholder_circle_v1');
      for (final other in [
        AssetReference(
          assetId: pinned.assetId,
          version: 2,
          sha256: pinned.sha256,
        ),
        AssetReference(assetId: pinned.assetId, version: 1, sha256: 'a' * 64),
        AssetReference(
          assetId: 'shape_circle',
          version: 1,
          sha256: pinned.sha256,
        ),
        null,
      ]) {
        expect(m.resolveReference(other), isNull, reason: '$other');
      }
      expect(QuestionnaireAssetManifest.empty.resolveReference(pinned), isNull);
    });
  });

  group('MOB6-09 local drafts: v0.5.2 answers behind a format marker', () {
    DraftRepository repo(MemoryDraftBox box) => DraftRepository(
      box: box,
      cipher: SecretCipher(),
      cryptoContext: (uid) async =>
          CryptoContext(secret: 'k-$uid', saltB64: 's'),
    );

    test(
      'a new row: format 2, encrypted v0.5.2 answers, no answer ids',
      () async {
        final box = MemoryDraftBox();
        const a = Answer(
          questionId: 'q1',
          type: QuestionType.yesNo,
          value: true,
        );
        await repo(box).save(
          'p1',
          const LocalDraft(
            attemptId: 'at1',
            versionId: 'v1',
            baseRevision: 3,
            dirty: true,
            answers: {'q1': a},
          ),
        );
        final row = (jsonDecode(box.rows.values.single) as Map);
        expect(row['format'], DraftRepository.format);
        expect(row['format'], 2);
        final payload = await SecretCipher().decrypt(
          row['payload'] as String,
          'k-p1',
        );
        expect(jsonDecode(payload), {
          'answers': [
            {'question_id': 'q1', 'type': 'yes_no', 'value': true},
          ],
        });
        expect((await repo(box).load('p1', 'at1'))!.answers['q1'], a);
        // The marker alone decides: the same row without it (or another
        // format) is not read, even though its answers would decode.
        for (final marker in [null, 1, 3]) {
          final copy = Map.of(row)..remove('format');
          if (marker != null) copy['format'] = marker;
          box.rows['p1::at1'] = jsonEncode(copy);
          expect(
            await repo(box).load('p1', 'at1'),
            isNull,
            reason: 'format $marker',
          );
        }
      },
    );
    test('an old MOB-3 row is ignored and the server copy wins', () async {
      final remote = MockQuestionnaireRemote();
      final assignment = (await remote.assignments()).items.first;
      final server = AttemptController(
        uid: 'p1',
        assignment: assignment,
        api: remote,
        drafts: repo(MemoryDraftBox()),
        debounce: Duration.zero,
      );
      await server.load();
      server.setAnswer('q_single', const AnswerValue(optionIds: ['o_b']));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      server.dispose();

      final box = MemoryDraftBox();
      final cipher = SecretCipher();
      box.rows['p1::${assignment.attemptId}'] = jsonEncode({
        'uid': 'p1',
        'attempt_id': assignment.attemptId,
        'version_id': assignment.versionId,
        'base_revision': 1,
        'dirty': true,
        'payload': await cipher.encrypt(
          jsonEncode({
            'answers': [
              {
                'answer_id': 'a1',
                'question_id': 'q_single',
                'option_ids': ['o_a'],
                'value': null,
                'text': null,
              },
            ],
            'answer_ids': {'q_single': 'a1'},
          }),
          'k-p1',
          's',
        ),
      });
      expect(await repo(box).load('p1', assignment.attemptId), isNull);
      final c = AttemptController(
        uid: 'p1',
        assignment: assignment,
        api: remote,
        drafts: repo(box),
        debounce: Duration.zero,
      );
      await c.load();
      expect(c.answers['q_single']!.value, 'o_b');
      expect(c.saveStatus, isNot(SaveStatus.conflict));
      c.dispose();
    });
  });

  group('MOB6-10 strict lists: a leaking item is skipped, never half-read', () {
    test('the other items still show', () {
      Map<String, Object?> item(String id, [Map<String, Object?>? extra]) => {
        'id': id,
        'relationship_id': 'r',
        'organization_id': 'o',
        'questionnaire_version_id': 'v',
        'attempt_id': 'at_$id',
        'title': {'en': id},
        'state': 'assigned',
        'created_at': '2026-10-20T08:00:00Z',
        ...?extra,
      };
      final page = parseAssignmentPage({
        'items': [
          item('a1'),
          item('a2', {'score': 3}),
          item('a3', {'review_status': 'done'}),
          item('a4'),
        ],
        'next_cursor': null,
      });
      expect(page.items.map((a) => a.assignmentId), ['a1', 'a4']);
      expect(
        () => parseAssignmentPage({
          'items': const [],
          'next_cursor': null,
          'total_scored': 1,
        }),
        _refused,
      );
    });
  });

  group(
    'MOB6-11 controller: below-minimum selections never reach the server',
    () {
      test(
        'kept and shown locally, sent once valid, submit blocked meanwhile',
        () async {
          final remote = MockQuestionnaireRemote();
          final c = AttemptController(
            uid: 'p1',
            assignment: (await remote.assignments()).items.first,
            api: remote,
            drafts: DraftRepository(
              box: MemoryDraftBox(),
              cipher: SecretCipher(),
              cryptoContext: (uid) async =>
                  CryptoContext(secret: 'k', saltB64: 's'),
            ),
            debounce: Duration.zero,
          );
          Future<void> settle() =>
              Future<void>.delayed(const Duration(milliseconds: 20));
          await c.load();
          c.setAnswer('q_multi', const AnswerValue(optionIds: ['o_a']));
          await settle();
          expect(c.answers['q_multi']!.optionIds, ['o_a']);
          expect(c.saveStatus, SaveStatus.saved, reason: 'no 400');
          expect(remote.answersOf('demo_attempt_en'), isEmpty);
          for (final e in {
            'q_single': const AnswerValue(optionIds: ['o_a']),
            'q_yes_no': const AnswerValue(yes: true),
            'q_likert': const AnswerValue(optionIds: ['o1']),
            'q_image_single': const AnswerValue(optionIds: ['img_circle']),
          }.entries) {
            c.setAnswer(e.key, e.value);
          }
          expect(await c.submit(), isFalse);
          expect(c.submitProblem, SubmitProblem.incomplete);
          expect(c.missing, ['q_multi']);
          expect(remote.committedSubmissions, 0);
          c.setAnswer('q_multi', const AnswerValue(optionIds: ['o_a', 'o_d']));
          await settle();
          expect(
            remote.answersOf('demo_attempt_en').map((a) => a.questionId),
            contains('q_multi'),
          );
          expect(await c.submit(), isTrue);
          expect(remote.committedSubmissions, 1);
          c.dispose();
        },
      );
    },
  );

  group('MOB6-12 an acknowledgement with extra keys is never read', () {
    test(
      'unconfirmed; the assignment decides; the retry reuses the key',
      () async {
        final remote = _LeakyAckRemote();
        var keys = 0;
        final c = AttemptController(
          uid: 'p1',
          assignment: (await remote.assignments()).items[2],
          api: remote,
          drafts: DraftRepository(
            box: MemoryDraftBox(),
            cipher: SecretCipher(),
            cryptoContext: (uid) async =>
                CryptoContext(secret: 'k', saltB64: 's'),
          ),
          debounce: Duration.zero,
          newKey: () => 'key-${keys++}',
        );
        await c.load();
        for (final e in {
          'q_single': const AnswerValue(optionIds: ['o_a']),
          'q_multi': const AnswerValue(optionIds: ['o_b']),
          'q_yes_no': const AnswerValue(yes: false),
          'q_likert': const AnswerValue(optionIds: ['o2']),
        }.entries) {
          c.setAnswer(e.key, e.value);
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
        // The leaky reply is refused, and the assignment says: submitted.
        expect(await c.submit(), isTrue);
        expect(c.phase, AttemptPhase.submitted);
        expect(remote.committedSubmissions, 1);
        expect(remote.submitKeys, ['key-${keys - 1}']);
        c.dispose();
      },
    );
  });

  group('MOB6-13 no MOB-3 wire names survive in the patient code', () {
    test('answer_id, option_ids, numeric, help_text, sources: gone', () {
      final old = RegExp(
        r"answer_id|option_ids|'option_id'|'question_id': a\.answerId|numeric|help_text|visual_description|'sources'|'rtl'|roman_ur|'free_text'",
      );
      final hits = <String>[];
      for (final f in dartFilesUnder('lib/questionnaires')) {
        // The bundled picture library keeps its own manifest.json format
        // (asset_id, kind, visual_description); it is not wire data.
        if (f.path.endsWith('asset_manifest.dart')) continue;
        final lines = codeOf(f).split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (old.hasMatch(lines[i])) hits.add('${f.path}:${i + 1}');
        }
      }
      expect(hits, isEmpty);
    });
  });
}

/// A remote whose submit reply carries an extra key (a leaking server).
class _LeakyAckRemote extends MockQuestionnaireRemote {
  final List<String> submitKeys = [];

  @override
  Future<SubmitAck> submit(
    String attemptId, {
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    submitKeys.add(idempotencyKey);
    final ack = await super.submit(
      attemptId,
      expectedRevision: expectedRevision,
      idempotencyKey: idempotencyKey,
    );
    return parseSubmitAck({
      'attempt_id': ack.attemptId,
      'assignment_id': ack.assignmentId,
      'submitted_at': ack.submittedAt.toIso8601String(),
      'status': 'submitted',
      'score': 12,
    });
  }
}
