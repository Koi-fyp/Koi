import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/core/crypto_context.dart';
import 'package:koi_mobile/platform/platform_client.dart';
import 'package:koi_mobile/questionnaires/attempt_controller.dart';
import 'package:koi_mobile/questionnaires/draft_store.dart';
import 'package:koi_mobile/questionnaires/mock_questionnaire_api.dart';
import 'package:koi_mobile/questionnaires/questionnaire_models.dart';

import '../support/mob1_fakes.dart';

final _assignment = MockQuestionnaireRemote.demoAssignments().first;

Map<String, Object?> _versionJson({
  bool approved = true,
  int schema = 1,
  String type = 'single_choice',
}) => {
  'version_id': 'v1',
  'questionnaire_id': 'q',
  'approved': approved,
  'schema_version': schema,
  'locale': 'en',
  'title': 'T',
  'questions': [
    {
      'id': 'q1',
      'type': type,
      'required': true,
      'prompt': 'Placeholder',
      'options': [
        {'id': 'a', 'label': 'A'},
        {'id': 'b', 'label': 'B'},
      ],
    },
  ],
};

/// Fills every required question of the English demo version.
const Map<String, Answer> _complete = {
  'q1': Answer(optionIds: ['opt_A']),
  'q2': Answer(optionIds: ['opt_B', 'opt_C']),
  'q3': Answer(optionIds: ['yes']),
  'q4': Answer(optionIds: ['l3']),
  'q6': Answer(optionIds: ['img_square']),
};

void main() {
  late MemoryDraftBox box;
  late DraftRepository drafts;
  late MockQuestionnaireRemote remote;

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
    assignment: _assignment,
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

  setUp(() {
    box = MemoryDraftBox();
    drafts = draftsOn(box);
    remote = MockQuestionnaireRemote();
  });

  group('MOB1-26 only approved, immutable, known versions render', () {
    test('unapproved, unknown schema and unknown type are refused', () {
      expect(
        () => QuestionnaireVersion.fromJson(_versionJson(approved: false)),
        throwsA(isA<UnsupportedQuestionnaireException>()),
      );
      expect(
        () => QuestionnaireVersion.fromJson(_versionJson(schema: 2)),
        throwsA(isA<UnsupportedQuestionnaireException>()),
      );
      expect(
        () => QuestionnaireVersion.fromJson(_versionJson(type: 'numeric')),
        throwsA(isA<UnsupportedQuestionnaireException>()),
      );
      expect(
        QuestionnaireVersion.fromJson(_versionJson()).questions.single.id,
        'q1',
      );
    });
    test('answers are sanitized against the pinned version', () {
      final v = QuestionnaireVersion.fromJson(_versionJson());
      final clean = sanitizeAnswers(v, const {
        'q1': Answer(optionIds: ['zzz', 'b', 'a']),
        'q9': Answer(optionIds: ['a']),
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
          assignment: const Assignment(
            assignmentId: 'demo-assignment-en',
            attemptId: 'demo-attempt-en',
            versionId: 'demo-form-ur-v1',
            title: 't',
            status: AttemptStatus.notStarted,
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
      c.setAnswer('q1', const Answer(optionIds: ['opt_A']));
      c.setAnswer('q1', const Answer(optionIds: ['opt_B']));
      c.setAnswer('q3', const Answer(optionIds: ['no']));
      expect(c.saveStatus, isNot(SaveStatus.saved));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await settle();
      expect(remote.saveDraftCalls, 1);
      expect(c.serverRevision, 1);
      expect(c.saveStatus, SaveStatus.saved);
      expect(remote.snapshot('demo-attempt-en').answers['q1']!.optionIds, [
        'opt_B',
      ]);
      c.setAnswer('q4', const Answer(optionIds: ['l2']));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await settle();
      expect(c.serverRevision, 2);
      c.dispose();
    });
    test('the local draft is encrypted and holds no plain answers', () async {
      final c = device();
      await c.load();
      c.setAnswer('q5', const Answer(text: 'my private words'));
      await settle();
      final raw = box.rows.values.single;
      expect(raw, isNot(contains('my private words')));
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
      a.setAnswer('q1', const Answer(optionIds: ['opt_C']));
      await settle();
      expect(a.saveStatus, SaveStatus.saved);
      final b = device(store: draftsOn(MemoryDraftBox()));
      await b.load();
      expect(b.answers['q1']!.optionIds, ['opt_C']);
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
      a.setAnswer('q1', const Answer(optionIds: ['opt_A']));
      await settle();
      expect(a.saveStatus, SaveStatus.offline);
      expect(a.hasUnsyncedChanges, isTrue);

      // Device B saves while A is offline.
      remote.offline = false;
      final b = device(store: draftsOn(MemoryDraftBox()));
      await b.load();
      b.setAnswer('q1', const Answer(optionIds: ['opt_B']));
      await settle();
      expect(remote.snapshot('demo-attempt-en').revision, 1);

      // A comes back online: conflict, the server answer is untouched.
      a.setAnswer('q3', const Answer(optionIds: ['yes']));
      await settle();
      expect(a.saveStatus, SaveStatus.conflict);
      expect(remote.snapshot('demo-attempt-en').answers['q1']!.optionIds, [
        'opt_B',
      ]);
      // While in conflict, edits are refused (nothing is merged).
      a.setAnswer('q4', const Answer(optionIds: ['l1']));
      expect(a.answers.containsKey('q4'), isFalse);

      await a.resolveUseServer();
      expect(a.saveStatus, isNot(SaveStatus.conflict));
      expect(a.answers['q1']!.optionIds, ['opt_B']);
      a.dispose();
      b.dispose();
    });
    test('resume with a stale local draft → conflict; "keep mine" is an explicit overwrite', () async {
      final a = device();
      await a.load();
      remote.offline = true;
      a.setAnswer('q1', const Answer(optionIds: ['opt_A']));
      await settle();
      a.dispose();
      remote.offline = false;
      final b = device(store: draftsOn(MemoryDraftBox()));
      await b.load();
      b.setAnswer('q1', const Answer(optionIds: ['opt_C']));
      await settle();
      b.dispose();

      final again = device(); // device A restarts with its stale draft
      await again.load();
      expect(again.saveStatus, SaveStatus.conflict);
      expect(again.answers['q1']!.optionIds, [
        'opt_C',
      ], reason: 'server shown first');
      await again.resolveKeepMine();
      await settle();
      expect(remote.snapshot('demo-attempt-en').answers['q1']!.optionIds, [
        'opt_A',
      ]);
      expect(again.saveStatus, SaveStatus.saved);
      again.dispose();
    });
  });

  group('MOB1-30 restart rules', () {
    test('unfinished: cleared on the server, local draft dropped', () async {
      final c = device();
      await c.load();
      c.setAnswer('q1', const Answer(optionIds: ['opt_A']));
      await settle();
      expect(await c.restart(), isTrue);
      expect(c.answers, isEmpty);
      expect(remote.snapshot('demo-attempt-en').answers, isEmpty);
      expect(c.index, 0);
      c.dispose();
    });
    test('submitted: refused, nothing cleared', () async {
      final c = device();
      await c.load();
      for (final e in _complete.entries) {
        c.setAnswer(e.key, e.value);
      }
      expect(await c.submit(), isTrue);
      expect(await c.restart(), isFalse);
      expect(
        remote.snapshot('demo-attempt-en').status,
        AttemptStatus.submitted,
      );
      expect(remote.snapshot('demo-attempt-en').answers, isNotEmpty);
      c.dispose();
    });
  });

  group('MOB1-31 duplicate submit / timeout = exactly one submission', () {
    test(
      'commit then timeout → status by idempotency key → success, 1 commit',
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
        c.setAnswer('q1', const Answer(optionIds: ['opt_A']));
        expect(await c.submit(), isFalse);
        expect(c.submitProblem, SubmitProblem.incomplete);
        expect(c.missing.first, 'q2');
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
      c.setAnswer('q1', const Answer(optionIds: ['opt_C']));
      await settle();
      expect(c.answers['q1']!.optionIds, ['opt_A']);
      expect(box.rows, isEmpty);
      expect(remote.snapshot('demo-attempt-en').answers['q1']!.optionIds, [
        'opt_A',
      ]);
      c.dispose();
    });
    test(
      'a stale offline draft can never reopen a submitted attempt',
      () async {
        final a = device();
        await a.load();
        remote.offline = true;
        a.setAnswer('q1', const Answer(optionIds: ['opt_C']));
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
        expect(remote.snapshot('demo-attempt-en').answers['q1']!.optionIds, [
          'opt_A',
        ]);
        back.dispose();
      },
    );
    test('the server saying attempt_submitted locks the open form', () async {
      final a = device();
      await a.load();
      final b = device(store: draftsOn(MemoryDraftBox()));
      await b.load();
      for (final e in _complete.entries) {
        b.setAnswer(e.key, e.value);
      }
      await b.submit();
      a.setAnswer('q1', const Answer(optionIds: ['opt_C']));
      await settle();
      expect(a.phase, AttemptPhase.submitted);
      expect(remote.snapshot('demo-attempt-en').answers['q1']!.optionIds, [
        'opt_A',
      ]);
      a.dispose();
      b.dispose();
    });
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
    test('mock remote follows the contract errors', () async {
      await expectLater(
        remote.saveDraft(
          'demo-attempt-en',
          expectedRevision: 5,
          answers: const {},
          clientMutationId: 'm',
        ),
        throwsA(
          isA<PlatformException>()
              .having((e) => e.code, 'code', PlatformErrorCode.revisionConflict)
              .having((e) => e.currentRevision, 'current', 0),
        ),
      );
    });
  });
}
