import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/core/crypto_context.dart';
import 'package:koi_mobile/platform/platform_client.dart';
import 'package:koi_mobile/questionnaires/attempt_controller.dart';
import 'package:koi_mobile/questionnaires/draft_store.dart';
import 'package:koi_mobile/questionnaires/mock_fixtures.dart';
import 'package:koi_mobile/questionnaires/mock_questionnaire_api.dart';
import 'package:koi_mobile/questionnaires/questionnaire_models.dart';
import 'package:koi_mobile/questionnaires/questionnaire_wire.dart';

import '../support/mob1_fakes.dart';

// MOB-3 rewrite: same MOB-1 IDs and behaviours, now on the contract v0.5.1
// flow (PATCH autosave, Restart = empty PATCH, POST submit) with the AI
// QuestionnaireDraft body (PROVISIONAL).

const _attempt = 'demo_attempt_en';

/// Fills every required question of the English all-types fixture.
const Map<String, AnswerValue> _complete = {
  'q_single': AnswerValue(optionIds: ['o_a']),
  'q_multi': AnswerValue(optionIds: ['o_b', 'o_c']),
  'q_yes_no': AnswerValue(optionIds: ['o_yes']),
  'q_likert': AnswerValue(optionIds: ['o3']),
  'q_numeric': AnswerValue(value: 4),
  'q_image_single': AnswerValue(optionIds: ['img_square']),
};

Map<String, Object?> _published({
  String status = 'published',
  String type = 'single',
}) => {
  'questionnaire_id': 'q',
  'version': 1,
  'status': status,
  'body': {
    'title': 'T',
    'language': 'en',
    'rtl': false,
    'questions': [
      {
        'question_id': 'q1',
        'type': type,
        'text': 'Placeholder',
        'options': [
          {'option_id': 'a', 'label': 'A'},
          {'option_id': 'b', 'label': 'B'},
        ],
      },
    ],
  },
};

void main() {
  late MemoryDraftBox box;
  late DraftRepository drafts;
  late MockQuestionnaireRemote remote;
  late Assignment assignment;

  DraftRepository draftsOn(MemoryDraftBox b) => DraftRepository(
    box: b,
    cipher: SecretCipher(),
    cryptoContext: (uid) async => CryptoContext(secret: 'k-$uid', saltB64: 's'),
  );

  AttemptController device({
    DraftRepository? store,
    Duration debounce = Duration.zero,
    String Function()? newKey,
  }) => AttemptController(
    uid: 'p1',
    assignment: assignment,
    api: remote,
    drafts: store ?? drafts,
    debounce: debounce,
    newKey: newKey,
  );

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  List<String>? serverOptions(String questionId) => remote
      .answersOf(_attempt)
      .where((a) => a.questionId == questionId)
      .firstOrNull
      ?.optionIds;

  setUp(() async {
    box = MemoryDraftBox();
    drafts = draftsOn(box);
    remote = MockQuestionnaireRemote();
    assignment = (await remote.assignments()).items.first;
  });

  group('MOB1-26 only published, known questionnaires render', () {
    test('unpublished and unknown types are refused', () {
      expect(
        () => parsePublishedQuestionnaire(_published(status: 'draft')),
        throwsA(isA<UnsupportedQuestionnaireException>()),
      );
      expect(
        () => parsePublishedQuestionnaire(_published(type: 'slider')),
        throwsA(isA<UnsupportedQuestionnaireException>()),
      );
      expect(
        parsePublishedQuestionnaire(_published()).questions.single.id,
        'q1',
      );
    });
    test('answers are sanitized against the pinned questionnaire', () {
      final v = parsePublishedQuestionnaire(_published());
      final clean = sanitizeAnswers(v, const {
        'q1': Answer(
          answerId: 'id1',
          questionId: 'q1',
          optionIds: ['zzz', 'b', 'a'],
        ),
        'q9': Answer(answerId: 'id9', questionId: 'q9', optionIds: ['a']),
      });
      expect(clean.keys, ['q1']);
      expect(clean['q1']!.optionIds, [
        'b',
      ], reason: 'single choice keeps one valid id');
    });
    test(
      'an attempt for another version is never shown (no cross-version merge)',
      () async {
        final c = AttemptController(
          uid: 'p1',
          assignment: Assignment(
            assignmentId: assignment.assignmentId,
            attemptId: assignment.attemptId,
            versionId: 'demo_version_ur',
            title: const {'en': 't'},
            state: AssignmentState.assigned,
          ),
          api: remote,
          drafts: drafts,
        );
        await c.load();
        expect(c.phase, AttemptPhase.unavailable);
        expect(c.loadError, AttemptLoadError.unsupported);
      },
    );
  });

  group('MOB1-27 debounced autosave with increasing revisions', () {
    test('quick edits → one save; revision goes up; status Saved', () async {
      final c = device(debounce: const Duration(milliseconds: 30));
      await c.load();
      expect(c.serverRevision, 0);
      c.setAnswer('q_single', const AnswerValue(optionIds: ['o_a']));
      c.setAnswer('q_single', const AnswerValue(optionIds: ['o_b']));
      c.setAnswer('q_yes_no', const AnswerValue(optionIds: ['o_no']));
      expect(c.saveStatus, isNot(SaveStatus.saved));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await settle();
      expect(remote.autosaveCalls, 1);
      expect(c.serverRevision, 1);
      expect(c.saveStatus, SaveStatus.saved);
      expect(serverOptions('q_single'), ['o_b']);
      c.setAnswer('q_likert', const AnswerValue(optionIds: ['o2']));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await settle();
      expect(c.serverRevision, 2);
      c.dispose();
    });
    test('the local draft is encrypted and holds no plain answers', () async {
      final c = device();
      await c.load();
      c.setAnswer('q_free_text', const AnswerValue(text: 'my private words'));
      await settle();
      final raw = box.rows.values.single;
      expect(raw, isNot(contains('my private words')));
      expect(raw, isNot(contains(c.answerIds['q_free_text']!)));
      expect((jsonDecode(raw) as Map).keys.toSet(), {
        'uid',
        'attempt_id',
        'version_id',
        'base_revision',
        'dirty',
        'payload',
      });
      c.dispose();
    });
  });

  group('MOB1-28 autosave + resume on a second device', () {
    test('device B sees device A\'s saved answers and revision', () async {
      final a = device();
      await a.load();
      a.setAnswer('q_single', const AnswerValue(optionIds: ['o_c']));
      await settle();
      expect(a.saveStatus, SaveStatus.saved);
      final b = device(store: draftsOn(MemoryDraftBox()));
      await b.load();
      expect(b.answers['q_single']!.optionIds, ['o_c']);
      expect(b.answers['q_single']!.answerId, a.answerIds['q_single']);
      expect(b.serverRevision, a.serverRevision);
      a.dispose();
      b.dispose();
    });
  });

  group('MOB1-29 offline edit vs a newer remote revision', () {
    test('offline → "Offline – not synced"; never overwrites the newer server copy', () async {
      final a = device();
      await a.load();
      remote.offline = true;
      a.setAnswer('q_single', const AnswerValue(optionIds: ['o_a']));
      await settle();
      expect(a.saveStatus, SaveStatus.offline);
      expect(a.hasUnsyncedChanges, isTrue);

      // Device B saves while A is offline.
      remote.offline = false;
      final b = device(store: draftsOn(MemoryDraftBox()));
      await b.load();
      b.setAnswer('q_single', const AnswerValue(optionIds: ['o_b']));
      await settle();
      expect(remote.revisionOf(_attempt), 1);

      // A comes back online: conflict, the server answer is untouched.
      a.setAnswer('q_yes_no', const AnswerValue(optionIds: ['o_yes']));
      await settle();
      expect(a.saveStatus, SaveStatus.conflict);
      expect(serverOptions('q_single'), ['o_b']);
      // While in conflict, edits are refused (nothing is merged).
      a.setAnswer('q_likert', const AnswerValue(optionIds: ['o1']));
      expect(a.answers.containsKey('q_likert'), isFalse);

      await a.resolveUseServer();
      expect(a.saveStatus, isNot(SaveStatus.conflict));
      expect(a.answers['q_single']!.optionIds, ['o_b']);
      a.dispose();
      b.dispose();
    });
    test('resume with a stale local draft → conflict; "keep mine" is an explicit overwrite', () async {
      final a = device();
      await a.load();
      remote.offline = true;
      a.setAnswer('q_single', const AnswerValue(optionIds: ['o_a']));
      await settle();
      a.dispose();
      remote.offline = false;
      final b = device(store: draftsOn(MemoryDraftBox()));
      await b.load();
      b.setAnswer('q_single', const AnswerValue(optionIds: ['o_c']));
      await settle();
      b.dispose();

      final again = device(); // device A restarts with its stale draft
      await again.load();
      expect(again.saveStatus, SaveStatus.conflict);
      expect(again.answers['q_single']!.optionIds, [
        'o_c',
      ], reason: 'server shown first');
      await again.resolveKeepMine();
      await settle();
      expect(serverOptions('q_single'), ['o_a']);
      expect(again.saveStatus, SaveStatus.saved);
      again.dispose();
    });
  });

  group('MOB1-30 restart rules', () {
    test(
      'unfinished: cleared on the server (empty PATCH), answers gone locally',
      () async {
        final c = device();
        await c.load();
        c.setAnswer('q_single', const AnswerValue(optionIds: ['o_a']));
        await settle();
        expect(await c.restart(), isTrue);
        expect(c.answers, isEmpty);
        expect(remote.answersOf(_attempt), isEmpty);
        expect(remote.autosaveBodies.last['answers'], isEmpty);
        expect(c.index, 0);
        c.dispose();
      },
    );
    test('submitted: refused, nothing cleared', () async {
      final c = device();
      await c.load();
      for (final e in _complete.entries) {
        c.setAnswer(e.key, e.value);
      }
      expect(await c.submit(), isTrue);
      expect(await c.restart(), isFalse);
      expect(remote.isSubmitted(_attempt), isTrue);
      expect(remote.answersOf(_attempt), isNotEmpty);
      c.dispose();
    });
  });

  group('MOB1-31 duplicate submit / timeout = exactly one submission', () {
    test(
      'commit then timeout → the assignment says submitted → success, 1 commit',
      () async {
        final c = device();
        await c.load();
        for (final e in _complete.entries) {
          c.setAnswer(e.key, e.value);
        }
        remote.commitThenTimeoutNextSubmit = true;
        expect(await c.submit(), isTrue);
        expect(c.phase, AttemptPhase.submitted);
        expect(remote.committedSubmissions, 1);
        c.dispose();
      },
    );
    test(
      'double tap and a retry with the stored key never submit twice',
      () async {
        var keys = 0;
        final c = device(newKey: () => 'key-${keys++}');
        await c.load();
        for (final e in _complete.entries) {
          c.setAnswer(e.key, e.value);
        }
        final both = await Future.wait([c.submit(), c.submit()]);
        expect(both.where((ok) => ok), isNotEmpty);
        expect(remote.committedSubmissions, 1);
        c.dispose();
      },
    );
    test('offline submit keeps the key; the retry re-uses it', () async {
      var keys = 0;
      final c = device(newKey: () => 'key-${keys++}');
      await c.load();
      for (final e in _complete.entries) {
        c.setAnswer(e.key, e.value);
      }
      await settle();
      remote.offline = true;
      expect(await c.submit(), isFalse);
      expect(c.submitProblem, SubmitProblem.offline);
      remote.offline = false;
      expect(await c.submit(), isTrue);
      expect(remote.committedSubmissions, 1);
      c.dispose();
    });
    test('"already submitted" (e.g. from another device) is success', () async {
      final c = device();
      await c.load();
      for (final e in _complete.entries) {
        c.setAnswer(e.key, e.value);
      }
      await settle();
      // Another device opens the same attempt and submits first.
      final other = device(store: draftsOn(MemoryDraftBox()));
      await other.load();
      expect(await other.submit(), isTrue);
      expect(await c.submit(), isTrue);
      expect(c.phase, AttemptPhase.submitted);
      expect(remote.committedSubmissions, 1);
      other.dispose();
      c.dispose();
    });
    test(
      'missing required answers block submit and point at the question',
      () async {
        final c = device();
        await c.load();
        c.setAnswer('q_single', const AnswerValue(optionIds: ['o_a']));
        expect(await c.submit(), isFalse);
        expect(c.submitProblem, SubmitProblem.incomplete);
        expect(c.missing.first, 'q_multi');
        expect(c.index, 1);
        expect(remote.committedSubmissions, 0);
        c.dispose();
      },
    );
  });

  group('MOB1-32 a submitted attempt stays locked', () {
    test('edits after submit are ignored; the draft is gone', () async {
      final c = device();
      await c.load();
      for (final e in _complete.entries) {
        c.setAnswer(e.key, e.value);
      }
      await c.submit();
      c.setAnswer('q_single', const AnswerValue(optionIds: ['o_c']));
      await settle();
      expect(c.answers['q_single']!.optionIds, ['o_a']);
      expect(box.rows, isEmpty);
      expect(serverOptions('q_single'), ['o_a']);
      c.dispose();
    });
    test(
      'a stale offline draft can never reopen a submitted attempt',
      () async {
        final a = device();
        await a.load();
        remote.offline = true;
        a.setAnswer('q_single', const AnswerValue(optionIds: ['o_c']));
        await settle();
        a.dispose();
        remote.offline = false;
        final b = device(store: draftsOn(MemoryDraftBox()));
        await b.load();
        for (final e in _complete.entries) {
          b.setAnswer(e.key, e.value);
        }
        expect(await b.submit(), isTrue);
        b.dispose();

        final back = device(); // A again, with its stale dirty draft
        await back.load();
        expect(back.phase, AttemptPhase.submitted);
        expect(box.rows, isEmpty, reason: 'stale draft discarded');
        expect(serverOptions('q_single'), ['o_a']);
        back.dispose();
      },
    );
    test(
      'the server refusing a save after submit locks the open form',
      () async {
        final a = device();
        await a.load();
        final b = device(store: draftsOn(MemoryDraftBox()));
        await b.load();
        for (final e in _complete.entries) {
          b.setAnswer(e.key, e.value);
        }
        await b.submit();
        a.setAnswer('q_single', const AnswerValue(optionIds: ['o_c']));
        await settle();
        expect(a.phase, AttemptPhase.submitted);
        expect(serverOptions('q_single'), ['o_a']);
        a.dispose();
        b.dispose();
      },
    );
  });

  group('MOB1-40 offline before the form loads', () {
    test(
      'shows unavailable (offline), nothing cached from elsewhere',
      () async {
        remote.offline = true;
        final c = device();
        await c.load();
        expect(c.phase, AttemptPhase.unavailable);
        expect(c.loadError, AttemptLoadError.offline);
        c.dispose();
      },
    );
    test('mock remote follows the contract errors (flat ErrorDTO)', () async {
      await expectLater(
        remote.autosave(
          _attempt,
          expectedRevision: 5,
          answers: const [],
          idempotencyKey: 'k',
        ),
        throwsA(
          isA<PlatformException>()
              .having((e) => e.code, 'code', PlatformErrorCode.conflict)
              .having((e) => e.status, 'status', 409)
              .having((e) => e.contractCode, 'contract code', 'conflict'),
        ),
      );
      // The demo fixtures parse with the app's own parser.
      expect(
        parsePublishedQuestionnaire(demoAllTypesEn()).questions,
        hasLength(8),
      );
    });
  });
}
