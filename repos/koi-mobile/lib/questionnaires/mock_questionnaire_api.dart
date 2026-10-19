import '../platform/platform_client.dart';
import 'questionnaire_api.dart';
import 'questionnaire_models.dart';

/// In-memory stand-in for the patient questionnaire endpoints: the demo
/// adapter for `--dart-define=KOI_MOCKS=true` (screens show "Demo data")
/// and the fake remote in tests. It follows the PROVISIONAL contract:
/// revision checks, terminal submission, idempotency keys.
///
/// All wording is PLACEHOLDER text. No clinical instrument wording is in the
/// app (decided MOB-1).
class MockQuestionnaireRemote implements QuestionnaireApi {
  MockQuestionnaireRemote({
    List<QuestionnaireVersion>? versions,
    List<Assignment>? assignments,
    DateTime Function()? now,
    this.latency = Duration.zero,
  }) : _now = now ?? DateTime.now {
    for (final v in versions ?? demoVersions()) {
      _versions[v.versionId] = v;
    }
    for (final a in assignments ?? demoAssignments()) {
      _assignments.add(a);
      _attempts[a.attemptId] = _AttemptRow(
        attemptId: a.attemptId,
        assignmentId: a.assignmentId,
        versionId: a.versionId,
      );
    }
  }

  final DateTime Function() _now;
  final Duration latency;
  final Map<String, QuestionnaireVersion> _versions = {};
  final List<Assignment> _assignments = [];
  final Map<String, _AttemptRow> _attempts = {};
  final Map<String, SubmitAck> _byKey = {};

  /// Test knob: every call fails like a dropped connection.
  bool offline = false;

  /// Test knob: the next submit COMMITS, then the response is lost
  /// (timeout), like a reply that never reached the phone.
  bool commitThenTimeoutNextSubmit = false;

  /// How many submissions were actually committed (must stay 1 per attempt).
  int committedSubmissions = 0;
  int saveDraftCalls = 0;

  @override
  bool get isMock => true;

  Future<void> _wire() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (offline) throw const PlatformException(PlatformErrorCode.network);
  }

  _AttemptRow _row(String id) =>
      _attempts[id] ??
      (throw const PlatformException(PlatformErrorCode.notFound));

  static PlatformException _submitted() => const PlatformException(
    PlatformErrorCode.attemptSubmitted,
    status: 409,
    body: {
      'error': {'code': 'attempt_submitted'},
    },
  );

  static PlatformException _conflict(int current) => PlatformException(
    PlatformErrorCode.revisionConflict,
    status: 409,
    body: {
      'error': {'code': 'revision_conflict', 'current_revision': current},
    },
  );

  /// Test helper: what the server holds now.
  Attempt snapshot(String attemptId) => _row(attemptId).toAttempt();

  @override
  Future<List<Assignment>> assignments() async {
    await _wire();
    return [
      for (final a in _assignments)
        Assignment(
          assignmentId: a.assignmentId,
          attemptId: a.attemptId,
          versionId: a.versionId,
          title: a.title,
          status: _row(a.attemptId).status,
          dueAt: a.dueAt,
        ),
    ];
  }

  @override
  Future<QuestionnaireVersion> version(String versionId) async {
    await _wire();
    return _versions[versionId] ??
        (throw const PlatformException(PlatformErrorCode.notFound));
  }

  @override
  Future<Attempt> attempt(String attemptId) async {
    await _wire();
    return _row(attemptId).toAttempt();
  }

  @override
  Future<DraftAck> saveDraft(
    String attemptId, {
    required int expectedRevision,
    required Map<String, Answer> answers,
    required String clientMutationId,
  }) async {
    await _wire();
    saveDraftCalls++;
    final r = _row(attemptId);
    if (r.status == AttemptStatus.submitted) throw _submitted();
    if (expectedRevision != r.revision) throw _conflict(r.revision);
    final version = _versions[r.versionId]!;
    r
      ..answers = sanitizeAnswers(version, answers)
      ..revision += 1
      ..status = AttemptStatus.inProgress;
    return DraftAck(revision: r.revision);
  }

  @override
  Future<Attempt> restart(
    String attemptId, {
    required int expectedRevision,
  }) async {
    await _wire();
    final r = _row(attemptId);
    if (r.status == AttemptStatus.submitted) throw _submitted();
    if (expectedRevision != r.revision) throw _conflict(r.revision);
    r
      ..answers = {}
      ..revision += 1
      ..status = AttemptStatus.notStarted;
    return r.toAttempt();
  }

  @override
  Future<SubmitAck> submit(
    String attemptId, {
    required String idempotencyKey,
    required int expectedRevision,
  }) async {
    await _wire();
    final again = _byKey[idempotencyKey];
    if (again != null) return again; // same key = the same submission
    final r = _row(attemptId);
    if (r.status == AttemptStatus.submitted) throw _submitted();
    if (expectedRevision != r.revision) throw _conflict(r.revision);
    final version = _versions[r.versionId]!;
    if (missingRequired(version, r.answers).isNotEmpty) {
      throw const PlatformException(PlatformErrorCode.conflict, status: 422);
    }
    r
      ..status = AttemptStatus.submitted
      ..submittedAt = _now()
      ..revision += 1;
    final ack = SubmitAck(attemptId: attemptId, submittedAt: r.submittedAt);
    _byKey[idempotencyKey] = ack;
    committedSubmissions++;
    if (commitThenTimeoutNextSubmit) {
      commitThenTimeoutNextSubmit = false;
      throw const PlatformException(PlatformErrorCode.timeout);
    }
    return ack;
  }

  @override
  Future<SubmitAck?> submissionStatus(
    String attemptId, {
    required String idempotencyKey,
  }) async {
    await _wire();
    return _byKey[idempotencyKey];
  }

  // ── Demo content: PLACEHOLDER wording only ────────────────────────────

  static List<Assignment> demoAssignments() => const [
    Assignment(
      assignmentId: 'demo-assignment-en',
      attemptId: 'demo-attempt-en',
      versionId: 'demo-form-en-v1',
      title: 'Placeholder form (English)',
      status: AttemptStatus.notStarted,
    ),
    Assignment(
      assignmentId: 'demo-assignment-ur',
      attemptId: 'demo-attempt-ur',
      versionId: 'demo-form-ur-v1',
      title: 'نمونہ فارم (اردو)',
      status: AttemptStatus.notStarted,
    ),
    Assignment(
      assignmentId: 'demo-assignment-roman',
      attemptId: 'demo-attempt-roman',
      versionId: 'demo-form-roman-v1',
      title: 'Namoona form (Roman Urdu)',
      status: AttemptStatus.notStarted,
    ),
  ];

  static List<QuestionnaireVersion> demoVersions() => [
    _demo(
      'demo-form-en-v1',
      QuestionnaireLocale.en,
      const _Words(
        title: 'Placeholder form (English)',
        instructions: 'Placeholder instructions. Answer each item.',
        question: 'Placeholder question',
        option: 'Option',
        yes: 'Yes',
        no: 'No',
        low: 'Placeholder low',
        high: 'Placeholder high',
        text: 'Placeholder short answer (optional)',
      ),
    ),
    _demo(
      'demo-form-ur-v1',
      QuestionnaireLocale.ur,
      const _Words(
        title: 'نمونہ فارم (اردو)',
        instructions: 'نمونہ ہدایات۔ ہر سوال کا جواب دیں۔',
        question: 'نمونہ سوال',
        option: 'اختیار',
        yes: 'ہاں',
        no: 'نہیں',
        low: 'نمونہ کم',
        high: 'نمونہ زیادہ',
        text: 'نمونہ مختصر جواب (اختیاری)',
      ),
    ),
    _demo(
      'demo-form-roman-v1',
      QuestionnaireLocale.romanUr,
      const _Words(
        title: 'Namoona form (Roman Urdu)',
        instructions: 'Namoona hidayat. Har sawal ka jawab dein.',
        question: 'Namoona sawal',
        option: 'Ikhtiyar',
        yes: 'Haan',
        no: 'Nahin',
        low: 'Namoona kam',
        high: 'Namoona zyada',
        text: 'Namoona mukhtasar jawab (ikhtiyari)',
      ),
    ),
  ];

  static QuestionnaireVersion _demo(
    String id,
    QuestionnaireLocale locale,
    _Words w,
  ) {
    List<ChoiceOption> abc() => [
      for (final l in ['A', 'B', 'C'])
        ChoiceOption(id: 'opt_$l', label: '${w.option} $l'),
    ];
    return QuestionnaireVersion(
      versionId: id,
      questionnaireId: 'demo-form',
      locale: locale,
      title: w.title,
      instructions: w.instructions,
      assetManifestVersion: 'v0-placeholder',
      questions: [
        Question(
          id: 'q1',
          type: QuestionType.singleChoice,
          required: true,
          prompt: '${w.question} 1',
          options: abc(),
        ),
        Question(
          id: 'q2',
          type: QuestionType.multiChoice,
          required: true,
          prompt: '${w.question} 2',
          options: abc(),
        ),
        Question(
          id: 'q3',
          type: QuestionType.yesNo,
          required: true,
          prompt: '${w.question} 3',
          options: [
            ChoiceOption(id: 'yes', label: w.yes),
            ChoiceOption(id: 'no', label: w.no),
          ],
        ),
        Question(
          id: 'q4',
          type: QuestionType.likert,
          required: true,
          prompt: '${w.question} 4',
          options: [
            ChoiceOption(id: 'l1', label: '1 · ${w.low}'),
            const ChoiceOption(id: 'l2', label: '2'),
            const ChoiceOption(id: 'l3', label: '3'),
            const ChoiceOption(id: 'l4', label: '4'),
            ChoiceOption(id: 'l5', label: '5 · ${w.high}'),
          ],
        ),
        Question(
          id: 'q5',
          type: QuestionType.shortText,
          required: false,
          prompt: w.text,
          maxLength: 200,
        ),
        Question(
          id: 'q6',
          type: QuestionType.imageSingleChoice,
          required: true,
          prompt: '${w.question} 6',
          options: const [
            ChoiceOption(id: 'img_circle', assetId: 'placeholder.circle.v1'),
            ChoiceOption(id: 'img_square', assetId: 'placeholder.square.v1'),
            ChoiceOption(
              id: 'img_triangle',
              assetId: 'placeholder.triangle.v1',
            ),
          ],
        ),
        Question(
          id: 'q7',
          type: QuestionType.imageMultiChoice,
          required: false,
          prompt: '${w.question} 7',
          options: [
            const ChoiceOption(
              id: 'img_circle',
              assetId: 'placeholder.circle.v1',
            ),
            const ChoiceOption(
              id: 'img_square',
              assetId: 'placeholder.square.v1',
            ),
            // Not in the manifest: shows the accessible fallback.
            ChoiceOption(
              id: 'img_missing',
              assetId: 'placeholder.missing.v1',
              label: '${w.option} D',
            ),
          ],
        ),
      ],
    );
  }
}

class _Words {
  const _Words({
    required this.title,
    required this.instructions,
    required this.question,
    required this.option,
    required this.yes,
    required this.no,
    required this.low,
    required this.high,
    required this.text,
  });
  final String title, instructions, question, option, yes, no, low, high, text;
}

class _AttemptRow {
  _AttemptRow({
    required this.attemptId,
    required this.assignmentId,
    required this.versionId,
  });

  final String attemptId;
  final String assignmentId;
  final String versionId;
  AttemptStatus status = AttemptStatus.notStarted;
  int revision = 0;
  Map<String, Answer> answers = {};
  DateTime? submittedAt;

  Attempt toAttempt() => Attempt(
    attemptId: attemptId,
    assignmentId: assignmentId,
    versionId: versionId,
    status: status,
    revision: revision,
    answers: Map.unmodifiable(answers),
    submittedAt: submittedAt,
  );
}
