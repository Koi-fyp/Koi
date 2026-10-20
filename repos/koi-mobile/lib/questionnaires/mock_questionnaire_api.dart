import '../platform/platform_client.dart';
import 'mock_fixtures.dart';
import 'questionnaire_api.dart';
import 'questionnaire_models.dart';
import 'questionnaire_wire.dart';

/// In-memory stand-in for the patient questionnaire endpoints: the demo
/// adapter for `--dart-define=KOI_MOCKS=true` (screens show "Demo data")
/// and the fake remote in tests. It follows contract v0.5.1 behaviour
/// (revision compare-and-set, terminal submission, idempotency keys, flat
/// ErrorDTO) and answers with the raw JSON a server would send, run
/// through the app's own parsers in questionnaire_wire.dart.
class MockQuestionnaireRemote implements QuestionnaireApi {
  MockQuestionnaireRemote({
    List<MockAssignmentSeed>? seeds,
    DateTime Function()? now,
    this.latency = Duration.zero,
    this.pageSize = 100,
  }) : _now = now ?? DateTime.now {
    for (final s in seeds ?? demoSeeds()) {
      _rows[s.attemptId] = _Row(s);
    }
  }

  final DateTime Function() _now;
  final Duration latency;
  final int pageSize;
  final Map<String, _Row> _rows = {};

  /// Test knob: every call fails like a dropped connection.
  bool offline = false;

  /// Test knob: the next submit COMMITS, then the response is lost
  /// (timeout), like a reply that never reached the phone.
  bool commitThenTimeoutNextSubmit = false;

  /// Test knob: the next submit answers 401 `unauthenticated` (the last
  /// sign-in is older than 5 minutes).
  bool requireRecentSignInNextSubmit = false;

  /// Test knob: the next autosave COMMITS, then times out.
  bool commitThenTimeoutNextAutosave = false;

  /// How many submissions were actually committed (must stay 1 per attempt).
  int committedSubmissions = 0;
  int autosaveCalls = 0;

  /// Every Idempotency-Key the autosave endpoint received, in order.
  final List<String> autosaveKeys = [];

  /// Every autosave body (the exact JSON the app sent), in order.
  final List<Map<String, Object?>> autosaveBodies = [];

  @override
  bool get isMock => true;

  Future<void> _wire() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (offline) throw const PlatformException(PlatformErrorCode.network);
  }

  _Row _row(String attemptId) =>
      _rows[attemptId] ??
      (throw const PlatformException(PlatformErrorCode.notFound));

  _Row _byAssignment(String assignmentId) =>
      _rows.values
          .where((r) => r.seed.assignmentId == assignmentId)
          .firstOrNull ??
      (throw const PlatformException(PlatformErrorCode.notFound));

  static PlatformException _error(
    PlatformErrorCode code,
    int status,
    String c,
  ) => PlatformException(
    code,
    status: status,
    body: {'code': c, 'request_id': 'mock_request', 'retryable': false},
  );

  static PlatformException _conflict() =>
      _error(PlatformErrorCode.conflict, 409, 'conflict');

  /// Test helper: the server's answers now (decoded like the app would).
  List<Answer> answersOf(String attemptId) => [
    for (final a in _row(attemptId).answers) decodeAnswer(a)!,
  ];

  int revisionOf(String attemptId) => _row(attemptId).revision;
  bool isSubmitted(String attemptId) => _row(attemptId).submittedAt != null;

  Map<String, Object?> _assignmentJson(_Row r) => {
    'id': r.seed.assignmentId,
    'relationship_id': 'demo_relationship',
    'organization_id': 'demo_org',
    'questionnaire_version_id': r.seed.versionId,
    'attempt_id': r.seed.attemptId,
    'title': r.seed.title,
    'state': r.submittedAt != null
        ? 'submitted'
        : r.revision == 0
        ? 'assigned'
        : 'in_progress',
    'created_at': '2026-10-20T08:00:00Z',
  };

  Map<String, Object?> _ackJson(_Row r) => {
    'attempt_id': r.seed.attemptId,
    'assignment_id': r.seed.assignmentId,
    'submitted_at': r.submittedAt!.toUtc().toIso8601String(),
    'status': 'submitted',
  };

  @override
  Future<AssignmentPage> assignments({String? cursor}) async {
    await _wire();
    final all = _rows.values.toList();
    final start = int.tryParse(cursor ?? '0') ?? 0;
    final end = (start + pageSize).clamp(0, all.length);
    return parseAssignmentPage({
      'items': [for (final r in all.sublist(start, end)) _assignmentJson(r)],
      'next_cursor': end < all.length ? '$end' : null,
    });
  }

  @override
  Future<AssignmentDetail> detail(String assignmentId) async {
    await _wire();
    final r = _byAssignment(assignmentId);
    if (r.submittedAt != null) {
      return parseAssignmentDetail({
        'assignment': _assignmentJson(r),
        'acknowledgement': _ackJson(r),
      });
    }
    return parseAssignmentDetail({
      'assignment': _assignmentJson(r),
      'questionnaire': r.seed.questionnaire,
      'attempt': {
        'id': r.seed.attemptId,
        'assignment_id': r.seed.assignmentId,
        'patient_uid': 'demo_patient',
        'version_id': r.seed.versionId,
        'status': r.revision == 0 ? 'not_started' : 'in_progress',
        'answers': r.answers,
        'revision': r.revision,
        'server_updated_at': '2026-10-20T08:00:00Z',
      },
    });
  }

  @override
  Future<AutosaveAck> autosave(
    String attemptId, {
    required int expectedRevision,
    required List<Answer> answers,
    required String idempotencyKey,
  }) async {
    await _wire();
    autosaveCalls++;
    autosaveKeys.add(idempotencyKey);
    final body = encodeAutosave(expectedRevision, answers);
    autosaveBodies.add(body);
    final r = _row(attemptId);
    final replay = r.autosaveByKey[idempotencyKey];
    if (replay != null) return replay; // same key = the same save
    if (r.submittedAt != null) throw _conflict();
    if (expectedRevision != r.revision) throw _conflict();
    final q = parsePublishedQuestionnaire(r.seed.questionnaire);
    final decoded = {
      for (final a in (body['answers']! as List).map(decodeAnswer).nonNulls)
        a.questionId: a,
    };
    if (decoded.length != answers.length) {
      throw _error(PlatformErrorCode.invalid, 400, 'invalid_request');
    }
    r
      ..answers = [
        for (final a in orderedAnswers(q, sanitizeAnswers(q, decoded)))
          encodeAnswer(a),
      ]
      ..revision += 1;
    final ack = parseAutosaveAck({
      'attempt_id': attemptId,
      'revision': r.revision,
      'server_updated_at': '2026-10-20T08:00:00Z',
      'status': 'in_progress',
    });
    r.autosaveByKey[idempotencyKey] = ack;
    if (commitThenTimeoutNextAutosave) {
      commitThenTimeoutNextAutosave = false;
      throw const PlatformException(PlatformErrorCode.timeout);
    }
    return ack;
  }

  @override
  Future<SubmitAck> submit(
    String attemptId, {
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    await _wire();
    if (requireRecentSignInNextSubmit) {
      requireRecentSignInNextSubmit = false;
      throw _error(PlatformErrorCode.reauthRequired, 401, 'unauthenticated');
    }
    final r = _row(attemptId);
    final again = r.submitKey == idempotencyKey && r.submittedAt != null;
    if (again) return parseSubmitAck(_ackJson(r)); // same key, same answer
    if (r.submittedAt != null) throw _conflict();
    if (expectedRevision != r.revision) throw _conflict();
    final q = parsePublishedQuestionnaire(r.seed.questionnaire);
    final held = {
      for (final a in r.answers.map(decodeAnswer)) a!.questionId: a,
    };
    if (missingRequired(q, held).isNotEmpty) {
      throw _error(PlatformErrorCode.invalid, 400, 'invalid_request');
    }
    r
      ..submittedAt = _now().toUtc()
      ..submitKey = idempotencyKey;
    committedSubmissions++;
    if (commitThenTimeoutNextSubmit) {
      commitThenTimeoutNextSubmit = false;
      throw const PlatformException(PlatformErrorCode.timeout);
    }
    return parseSubmitAck(_ackJson(r));
  }

  // ── Demo content: PLACEHOLDER wording only ────────────────────────────

  static List<MockAssignmentSeed> demoSeeds() => [
    MockAssignmentSeed(
      assignmentId: 'demo_assignment_en',
      attemptId: 'demo_attempt_en',
      versionId: 'demo_version_en',
      title: const {'en': 'Placeholder form (English)'},
      questionnaire: demoAllTypesEn(),
    ),
    MockAssignmentSeed(
      assignmentId: 'demo_assignment_ur',
      attemptId: 'demo_attempt_ur',
      versionId: 'demo_version_ur',
      title: const {'ur': 'نمونہ فارم (اردو)'},
      questionnaire: demoUrdu(),
    ),
    MockAssignmentSeed(
      assignmentId: 'demo_assignment_roman',
      attemptId: 'demo_attempt_roman',
      versionId: 'demo_version_roman',
      title: const {'ur-Latn': 'Namoona form (Roman Urdu)'},
      questionnaire: demoRomanUrdu(),
    ),
  ];
}

/// One demo assignment: its ids, LocalizedText title and the raw
/// PublishedQuestionnaire JSON.
class MockAssignmentSeed {
  const MockAssignmentSeed({
    required this.assignmentId,
    required this.attemptId,
    required this.versionId,
    required this.title,
    required this.questionnaire,
  });

  final String assignmentId;
  final String attemptId;
  final String versionId;
  final Map<String, String> title;
  final Map<String, Object?> questionnaire;
}

class _Row {
  _Row(this.seed);
  final MockAssignmentSeed seed;
  int revision = 0;

  /// Stored exactly as the wire carries them.
  List<Map<String, Object?>> answers = [];
  DateTime? submittedAt;
  String? submitKey;
  final Map<String, AutosaveAck> autosaveByKey = {};
}
