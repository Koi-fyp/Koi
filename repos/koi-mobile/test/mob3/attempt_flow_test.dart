import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/core/crypto_context.dart';
import 'package:koi_mobile/platform/platform_client.dart';
import 'package:koi_mobile/questionnaires/attempt_controller.dart';
import 'package:koi_mobile/questionnaires/draft_store.dart';
import 'package:koi_mobile/questionnaires/mock_fixtures.dart';
import 'package:koi_mobile/questionnaires/mock_questionnaire_api.dart';
import 'package:koi_mobile/questionnaires/questionnaire_api.dart';
import 'package:koi_mobile/questionnaires/questionnaire_flags.dart';
import 'package:koi_mobile/questionnaires/questionnaire_models.dart';
import 'package:koi_mobile/questionnaires/questionnaire_providers.dart';
import 'package:koi_mobile/questionnaires/questionnaire_screens.dart';
import 'package:koi_mobile/questionnaires/questionnaire_wire.dart';

import '../support/mob1_fakes.dart';
import '../support/mob3_support.dart';
import '../support/real_fonts.dart';

typedef _Req = ({
  String method,
  Uri uri,
  Map<String, String> headers,
  String? body,
});

/// A platform transport scripted per call; a handler may throw (timeout).
class _ScriptTransport implements PlatformTransport {
  _ScriptTransport(this.handle);
  final PlatformHttpResponse Function(_Req r) handle;
  final List<_Req> requests = [];

  @override
  Future<PlatformHttpResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async {
    final r = (method: method, uri: uri, headers: headers, body: body);
    requests.add(r);
    return handle(r);
  }
}

HttpQuestionnaireApi _http(_ScriptTransport t) => HttpQuestionnaireApi(
  PlatformClient(
    base: Uri.parse('https://platform.test'),
    transport: t,
    idToken: () async => 'tok',
    refreshIdToken: () async => 'tok2',
  ),
);

PlatformHttpResponse _json(int status, Object body) =>
    PlatformHttpResponse(status, jsonEncode(body));

Map<String, Object?> _errorDto(String code) => {
  'code': code,
  'request_id': 'req_1',
  'retryable': false,
};

Map<String, Object?> _assignmentJson({String state = 'in_progress'}) => {
  'id': 'as1',
  'relationship_id': 'rel1',
  'organization_id': 'org1',
  'questionnaire_version_id': 'ver1',
  'attempt_id': 'at1',
  'title': {'en': 'Form'},
  'state': state,
  'created_at': '2026-10-20T08:00:00Z',
};

Map<String, Object?> _openDetail(
  int revision, {
  List<Object?> answers = const [],
}) => {
  'assignment': _assignmentJson(),
  'questionnaire': demoAllTypesEn('ver1'),
  'attempt': {
    'id': 'at1',
    'assignment_id': 'as1',
    'patient_uid': 'p1',
    'version_id': 'ver1',
    'status': 'in_progress',
    'answers': answers,
    'revision': revision,
    'server_updated_at': '2026-10-20T08:00:00Z',
  },
};

Map<String, Object?> _submittedDetail() => {
  'assignment': _assignmentJson(state: 'submitted'),
  'acknowledgement': {
    'attempt_id': 'at1',
    'assignment_id': 'as1',
    'submitted_at': '2026-10-20T09:15:00Z',
    'status': 'submitted',
  },
};

Map<String, Object?> _ack(int revision) => {
  'attempt_id': 'at1',
  'revision': revision,
  'server_updated_at': '2026-10-20T08:00:00Z',
  'status': 'in_progress',
};

const _assignment = Assignment(
  assignmentId: 'as1',
  attemptId: 'at1',
  versionId: 'ver1',
  title: {'en': 'Form'},
  state: AssignmentState.inProgress,
);

DraftRepository _drafts(MemoryDraftBox b, {bool enabled = true}) =>
    DraftRepository(
      box: b,
      cipher: SecretCipher(),
      cryptoContext: (uid) async =>
          CryptoContext(secret: 'k-$uid', saltB64: 's'),
      enabled: enabled,
    );

Future<void> _settle() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late MockQuestionnaireRemote remote;
  late Assignment demo;

  AttemptController device({
    QuestionnaireApi? api,
    Assignment? assignment,
    Stream<bool>? online,
    MemoryDraftBox? box,
    bool drafts = true,
    String Function()? newKey,
  }) => AttemptController(
    uid: 'p1',
    assignment: assignment ?? demo,
    api: api ?? remote,
    drafts: _drafts(box ?? MemoryDraftBox(), enabled: drafts),
    debounce: Duration.zero,
    onlineChanges: online,
    newKey: newKey,
  );

  setUp(() async {
    remote = MockQuestionnaireRemote();
    demo = (await remote.assignments()).items.first;
  });

  group(
    'MOB3-18 autosave = PATCH /patient/attempts/{id} with Answer[] (v0.5.1)',
    () {
      test('path, method, body keys and Idempotency-Key', () async {
        final t = _ScriptTransport(
          (r) => r.method == 'GET'
              ? _json(200, _openDetail(0))
              : _json(200, _ack(1)),
        );
        final c = device(api: _http(t), assignment: _assignment);
        await c.load();
        expect(t.requests.single.uri.path, '/api/v1/patient/assignments/as1');
        c.setAnswer('q_single', const AnswerValue(optionIds: ['o_a']));
        await _settle();
        final patch = t.requests.last;
        expect(patch.method, 'PATCH');
        expect(
          patch.uri.toString(),
          'https://platform.test/api/v1/patient/attempts/at1',
        );
        expect(patch.headers['Authorization'], 'Bearer tok');
        expect(patch.headers['Idempotency-Key'], isNotEmpty);
        final body = jsonDecode(patch.body!) as Map;
        expect(body.keys.toSet(), {'expected_revision', 'answers'});
        expect(body['expected_revision'], 0);
        // MOB-6: the contract v0.5.2 Answer, exactly.
        expect((body['answers'] as List).single, {
          'question_id': 'q_single',
          'type': 'single_choice',
          'value': 'o_a',
        });
        expect(c.serverRevision, 1);
        c.dispose();
      });
      test(
        'a retry of the same save reuses its key; a new edit gets a new one',
        () async {
          final online = StreamController<bool>.broadcast();
          final c = device(online: online.stream);
          await c.load();
          remote.commitThenTimeoutNextAutosave = true;
          c.setAnswer('q_single', const AnswerValue(optionIds: ['o_a']));
          await _settle();
          expect(c.saveStatus, SaveStatus.offline);
          online.add(true); // connection back → the SAME save again
          await _settle();
          expect(remote.autosaveKeys, hasLength(2));
          expect(remote.autosaveKeys[1], remote.autosaveKeys[0]);
          expect(
            remote.revisionOf('demo_attempt_en'),
            1,
            reason: 'applied once',
          );
          expect(c.saveStatus, SaveStatus.saved);
          c.setAnswer('q_single', const AnswerValue(optionIds: ['o_b']));
          await _settle();
          expect(remote.autosaveKeys[2], isNot(remote.autosaveKeys[0]));
          c.dispose();
          await online.close();
        },
      );
    },
  );

  group('MOB3-19 Restart = the same PATCH with an empty answers array', () {
    test(
      'no restart endpoint exists; expected_revision is the current one',
      () async {
        final t = _ScriptTransport((r) {
          if (r.method == 'GET') return _json(200, _openDetail(4));
          return _json(200, _ack(5));
        });
        final c = device(api: _http(t), assignment: _assignment);
        await c.load();
        expect(await c.restart(), isTrue);
        final patch = t.requests.last;
        expect(patch.method, 'PATCH');
        expect(patch.uri.path, '/api/v1/patient/attempts/at1');
        expect(jsonDecode(patch.body!), {
          'expected_revision': 4,
          'answers': <Object?>[],
        });
        expect(c.serverRevision, 5);
        final code = [
          for (final f in dartFilesUnder('lib/questionnaires')) codeOf(f),
        ].join('\n');
        expect(code, isNot(contains('/restart')));
        expect(code, isNot(contains('/draft')));
        expect(code, isNot(contains('/submission')));
        c.dispose();
      },
    );
  });

  group('MOB3-20 409 conflict → re-read the assignment → the user chooses', () {
    test('a newer revision elsewhere shows the conflict choice', () async {
      var gets = 0;
      final t = _ScriptTransport((r) {
        if (r.method == 'GET') {
          gets++;
          return _json(200, _openDetail(gets == 1 ? 0 : 3));
        }
        return _json(409, _errorDto('conflict'));
      });
      final c = device(api: _http(t), assignment: _assignment);
      await c.load();
      c.setAnswer('q_single', const AnswerValue(optionIds: ['o_a']));
      await _settle();
      expect(c.saveStatus, SaveStatus.conflict);
      expect(c.remoteRevision, 3);
      expect(gets, 2, reason: 'detail re-read once');
      c.dispose();
    });
    test(
      'a conflict because it was submitted elsewhere locks the form',
      () async {
        var gets = 0;
        final t = _ScriptTransport((r) {
          if (r.method == 'GET') {
            gets++;
            return _json(200, gets == 1 ? _openDetail(0) : _submittedDetail());
          }
          return _json(409, _errorDto('conflict'));
        });
        final c = device(api: _http(t), assignment: _assignment);
        await c.load();
        c.setAnswer('q_single', const AnswerValue(optionIds: ['o_a']));
        await _settle();
        expect(c.phase, AttemptPhase.submitted);
        expect(c.submittedAt, DateTime.utc(2026, 10, 20, 9, 15));
        c.dispose();
      },
    );
  });

  group('MOB3-21 submit = POST …/submit, one key for every retry', () {
    test('timeout → assignment not submitted → unconfirmed; the retry reuses the key', () async {
      var posts = 0;
      final t = _ScriptTransport((r) {
        if (r.method == 'GET') {
          return _json(200, _openDetail(1, answers: const []));
        }
        if (r.method == 'POST') {
          posts++;
          if (posts == 1) {
            throw const PlatformException(PlatformErrorCode.timeout);
          }
          return _json(200, {
            'attempt_id': 'at1',
            'assignment_id': 'as1',
            'submitted_at': '2026-10-20T09:15:00Z',
            'status': 'submitted',
          });
        }
        return _json(200, _ack(2));
      });
      final c = device(api: _http(t), assignment: _assignment);
      await c.load();
      // Make the form complete without sending a PATCH first: optional-only
      // checks are the server's job; here every required answer is set.
      for (final q in c.questionnaire!.questions.where((q) => q.required)) {
        c.setAnswer(
          q.id,
          q.type == QuestionType.yesNo
              ? const AnswerValue(yes: true)
              : AnswerValue(
                  optionIds: [
                    for (final o in q.options.take(
                      q.minSelections > 1 ? q.minSelections : 1,
                    ))
                      o.id,
                  ],
                ),
        );
      }
      await _settle();
      expect(await c.submit(), isFalse);
      expect(c.submitProblem, SubmitProblem.unconfirmed);
      expect(await c.submit(), isTrue);
      final submits = t.requests.where((r) => r.method == 'POST').toList();
      expect(submits, hasLength(2));
      expect(submits[0].uri.path, '/api/v1/patient/attempts/at1/submit');
      expect(jsonDecode(submits[0].body!), {'expected_revision': 2});
      expect(
        submits[1].headers['Idempotency-Key'],
        submits[0].headers['Idempotency-Key'],
      );
      expect(c.phase, AttemptPhase.submitted);
      c.dispose();
    });
  });

  group('MOB3-22 submit needs a recent sign-in', () {
    test(
      '401 unauthenticated → reauth problem; the retry reuses the key',
      () async {
        var keys = 0;
        final c = device(newKey: () => 'key-${keys++}');
        await c.load();
        for (final e in {
          'q_single': const AnswerValue(optionIds: ['o_a']),
          'q_multi': const AnswerValue(optionIds: ['o_a', 'o_b']),
          'q_yes_no': const AnswerValue(yes: true),
          'q_likert': const AnswerValue(optionIds: ['o1']),
          'q_image_single': const AnswerValue(optionIds: ['img_circle']),
        }.entries) {
          c.setAnswer(e.key, e.value);
        }
        await _settle();
        remote.requireRecentSignInNextSubmit = true;
        expect(await c.submit(), isFalse);
        expect(c.submitProblem, SubmitProblem.reauth);
        expect(c.phase, AttemptPhase.answering);
        expect(await c.submit(), isTrue);
        expect(remote.committedSubmissions, 1);
        c.dispose();
      },
    );
    group('on screen', () {
      useRealFonts();
      setUp(() => FlutterSecureStorage.setMockInitialValues({}));
      testWidgets('the password sheet opens, then the same submit completes', (
        tester,
      ) async {
        final r = MockQuestionnaireRemote();
        final seed = MockQuestionnaireRemote.demoSeeds()[2]; // roman_ur
        final h = await pumpRunnerFor(tester, r, seed);
        h.auth.accounts['p@x'] = ('p1', 'pw');
        final q = parsePublished(seed);
        for (final x in q.questions) {
          await answerAndNext(tester, x);
        }
        r.requireRecentSignInNextSubmit = true;
        await tester.ensureVisible(find.byKey(const Key('q-submit')));
        await tester.tap(find.byKey(const Key('q-submit')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('care-reauth')), findsOneWidget);
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('care-reauth-password')),
            matching: find.byType(TextField),
          ),
          'pw',
        );
        await tester.tap(find.byKey(const Key('care-reauth-confirm')));
        await tester.pumpAndSettle();
        expect(find.text(AcknowledgementView.title), findsOneWidget);
        expect(r.committedSubmissions, 1);
      });
    });
  });

  group('MOB3-23 offline: editable and queued; submit needs the network', () {
    test(
      'edits continue offline and are sent when the connection is back',
      () async {
        final online = StreamController<bool>.broadcast();
        final c = device(online: online.stream);
        await c.load();
        remote.offline = true;
        c.setAnswer('q_single', const AnswerValue(optionIds: ['o_a']));
        await _settle();
        c.setAnswer('q_yes_no', const AnswerValue(yes: false));
        await _settle();
        expect(c.saveStatus, SaveStatus.offline);
        expect(c.answers.keys, containsAll(['q_single', 'q_yes_no']));
        for (final e in {
          'q_multi': const AnswerValue(optionIds: ['o_a', 'o_b']),
          'q_likert': const AnswerValue(optionIds: ['o1']),
          'q_image_single': const AnswerValue(optionIds: ['img_circle']),
        }.entries) {
          c.setAnswer(e.key, e.value);
        }
        expect(await c.submit(), isFalse);
        expect(c.submitProblem, SubmitProblem.offline);
        expect(remote.committedSubmissions, 0);
        remote.offline = false;
        online.add(true);
        await _settle();
        expect(c.saveStatus, SaveStatus.saved);
        expect(
          remote.answersOf('demo_attempt_en').map((a) => a.questionId),
          containsAllInOrder(['q_single', 'q_multi', 'q_yes_no']),
        );
        c.dispose();
        await online.close();
      },
    );
  });

  group('MOB3-24 a submitted assignment shows only the acknowledgement', () {
    test('no questionnaire is parsed; the attempt is locked', () async {
      final t = _ScriptTransport((r) => _json(200, _submittedDetail()));
      final c = device(api: _http(t), assignment: _assignment);
      await c.load();
      expect(c.phase, AttemptPhase.submitted);
      expect(c.questionnaire, isNull);
      expect(c.submittedAt, DateTime.utc(2026, 10, 20, 9, 15));
      c.setAnswer('q_single', const AnswerValue(optionIds: ['o_a']));
      expect(c.answers, isEmpty);
      expect(t.requests, hasLength(1));
      c.dispose();
    });
  });

  group('MOB3-25 assignment list: LocalizedText titles, every page', () {
    test('title in the Settings language, else English, else Roman Urdu', () {
      const a = Assignment(
        assignmentId: 'a',
        attemptId: 'b',
        versionId: 'c',
        title: {'en': 'English', 'ur': 'اردو', 'ur-Latn': 'Roman'},
        state: AssignmentState.assigned,
      );
      expect(a.titleFor('ur'), 'اردو');
      expect(a.titleFor('en'), 'English');
      const roman = Assignment(
        assignmentId: 'a',
        attemptId: 'b',
        versionId: 'c',
        title: {'ur-Latn': 'Roman'},
        state: AssignmentState.assigned,
      );
      expect(roman.titleFor('ur'), 'Roman');
    });
    test('GET /patient/assignments with limit + cursor', () async {
      final t = _ScriptTransport(
        (r) => _json(200, {
          'items': [
            _assignmentJson(),
            {'id': 'broken'},
          ],
          'next_cursor': 'next_1',
        }),
      );
      final page = await _http(t).assignments(cursor: 'c1');
      expect(t.requests.single.uri.path, '/api/v1/patient/assignments');
      expect(t.requests.single.uri.queryParameters, {
        'limit': '100',
        'cursor': 'c1',
      });
      expect(
        page.items.single.assignmentId,
        'as1',
        reason: 'broken item skipped',
      );
      expect(page.nextCursor, 'next_1');
    });
    group('on screen', () {
      useRealFonts();
      setUp(() => FlutterSecureStorage.setMockInitialValues({}));
      testWidgets('all pages are listed', (tester) async {
        final r = MockQuestionnaireRemote(pageSize: 1);
        final h = Mob1Harness(
          user: AccountFakeAuth.registered('p1', 'p@x'),
          caps: {'p1': patientCaps},
          questionnaires: r,
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: h.overrides,
            child: const MaterialApp(home: QuestionnaireListScreen()),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Placeholder form (English)'), findsOneWidget);
        expect(find.text('نمونہ فارم (اردو)'), findsOneWidget);
        expect(find.text('Namoona form (Roman Urdu)'), findsOneWidget);
        expect(find.text('Not started'), findsNWidgets(3));
      });
    });
  });

  group('MOB3-26 flat ErrorDTO codes map to the right state', () {
    test(
      '400 invalid_request on autosave → "Not saved" (not "Offline")',
      () async {
        final t = _ScriptTransport((r) {
          if (r.method == 'GET') return _json(200, _openDetail(0));
          return _json(400, _errorDto('invalid_request'));
        });
        final c = device(api: _http(t), assignment: _assignment);
        await c.load();
        c.setAnswer('q_single', const AnswerValue(optionIds: ['o_a']));
        await _settle();
        expect(c.saveStatus, SaveStatus.notSaved);
        expect(c.answers['q_single']!.optionIds, [
          'o_a',
        ], reason: 'still editable');
        c.dispose();
      },
    );
    test(
      '401 unauthenticated on POST → reauthRequired; 409 → conflict',
      () async {
        final t = _ScriptTransport(
          (r) => r.uri.path.endsWith('/submit')
              ? _json(401, _errorDto('unauthenticated'))
              : _json(409, _errorDto('conflict')),
        );
        final api = _http(t);
        await expectLater(
          api.submit('at1', expectedRevision: 1, idempotencyKey: 'k'),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              PlatformErrorCode.reauthRequired,
            ),
          ),
        );
        await expectLater(
          api.autosave(
            'at1',
            expectedRevision: 1,
            answers: const [],
            idempotencyKey: 'k',
          ),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              PlatformErrorCode.conflict,
            ),
          ),
        );
      },
    );
  });

  group('MOB3-27 the local draft sits behind ONE flag', () {
    test(
      'the provider uses kQuestionnaireLocalDrafts (documented, now true)',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        expect(
          container.read(draftRepositoryProvider).enabled,
          kQuestionnaireLocalDrafts,
        );
        expect(kQuestionnaireLocalDrafts, isTrue);
        final flags = File('lib/questionnaires/questionnaire_flags.dart')
            .readAsStringSync();
        expect(flags, contains('set this to false'));
      },
    );
    test('on: answers encrypted; off: nothing written or read', () async {
      final on = MemoryDraftBox();
      final c = device(box: on);
      await c.load();
      c.setAnswer('q_short_text', const AnswerValue(text: 'private words'));
      await _settle();
      final row = on.rows.values.single;
      expect(row, isNot(contains('private words')));
      expect(row, isNot(contains('q_short_text')));
      c.dispose();

      final off = MemoryDraftBox();
      final d = device(box: off, drafts: false);
      await d.load();
      d.setAnswer('q_short_text', const AnswerValue(text: 'private words'));
      await _settle();
      expect(off.rows, isEmpty);
      off.rows['p1::demo_attempt_en'] = on.rows.values.single;
      expect(
        await _drafts(off, enabled: false).load('p1', 'demo_attempt_en'),
        isNull,
      );
      await _drafts(off, enabled: false).deleteAllFor('p1');
      expect(off.rows, isEmpty, reason: 'old rows still deleted');
      d.dispose();
    });
  });
}

PublishedQuestionnaire parsePublished(MockAssignmentSeed s) =>
    parsePatientQuestionnaire(s.questionnaire);
