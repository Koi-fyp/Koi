import '../platform/platform_client.dart';
import 'questionnaire_models.dart';

/// The patient's questionnaire endpoints. PROVISIONAL (no web contract yet;
/// KOI_MOB1_PROVISIONAL_CONTRACTS.md). Every call is authenticated with the
/// Firebase ID token; the server decides what this uid may see. The app
/// never calls psychologist-only, review or AI endpoints.
abstract interface class QuestionnaireApi {
  /// Demo data (KOI_MOCKS): the screens show the "Demo data" badge.
  bool get isMock;

  Future<List<Assignment>> assignments();

  /// An approved, immutable version. Throws
  /// [UnsupportedQuestionnaireException] for anything else.
  Future<QuestionnaireVersion> version(String versionId);

  Future<Attempt> attempt(String attemptId);

  /// Autosave of whitelisted answer fields with the revision the client
  /// last saw. 409 `revision_conflict` when the server is newer; 409/423
  /// `attempt_submitted` once submitted.
  Future<DraftAck> saveDraft(
    String attemptId, {
    required int expectedRevision,
    required Map<String, Answer> answers,
    required String clientMutationId,
  });

  /// Clears an UNFINISHED attempt (server-authorized; refused once
  /// submitted). Returns the fresh attempt with a new revision.
  Future<Attempt> restart(String attemptId, {required int expectedRevision});

  /// The ONLY way to submit. Same [idempotencyKey] = same submission.
  Future<SubmitAck> submit(
    String attemptId, {
    required String idempotencyKey,
    required int expectedRevision,
  });

  /// After a timeout: did the submission with [idempotencyKey] land? null =
  /// not found (safe to send again with the SAME key).
  Future<SubmitAck?> submissionStatus(
    String attemptId, {
    required String idempotencyKey,
  });
}

class HttpQuestionnaireApi implements QuestionnaireApi {
  HttpQuestionnaireApi(this.client);
  final PlatformClient client;

  static const String _p = '/api/v1/patient';

  @override
  bool get isMock => false;

  @override
  Future<List<Assignment>> assignments() async {
    final j = asJsonMap(await client.getJson('$_p/assignments'));
    return [
      for (final a in asJsonList(j['assignments'], 'assignments'))
        Assignment.fromJson(a),
    ];
  }

  @override
  Future<QuestionnaireVersion> version(String versionId) async =>
      QuestionnaireVersion.fromJson(
        await client.getJson(
          '$_p/questionnaire-versions/${Uri.encodeComponent(versionId)}',
        ),
      );

  @override
  Future<Attempt> attempt(String attemptId) async => Attempt.fromJson(
    await client.getJson('$_p/attempts/${Uri.encodeComponent(attemptId)}'),
  );

  @override
  Future<DraftAck> saveDraft(
    String attemptId, {
    required int expectedRevision,
    required Map<String, Answer> answers,
    required String clientMutationId,
  }) async {
    final j = asJsonMap(
      await client.sendJson(
        'PUT',
        '$_p/attempts/${Uri.encodeComponent(attemptId)}/draft',
        {
          'expected_revision': expectedRevision,
          'client_mutation_id': clientMutationId,
          'answers': {for (final e in answers.entries) e.key: e.value.toJson()},
        },
      ),
    );
    return DraftAck(revision: reqInt(j, 'revision'));
  }

  @override
  Future<Attempt> restart(
    String attemptId, {
    required int expectedRevision,
  }) async => Attempt.fromJson(
    await client.sendJson(
      'POST',
      '$_p/attempts/${Uri.encodeComponent(attemptId)}/restart',
      {'expected_revision': expectedRevision},
    ),
  );

  @override
  Future<SubmitAck> submit(
    String attemptId, {
    required String idempotencyKey,
    required int expectedRevision,
  }) async => SubmitAck.fromJson(
    await client.sendJson(
      'POST',
      '$_p/attempts/${Uri.encodeComponent(attemptId)}/submit',
      {'expected_revision': expectedRevision},
      headers: {'Idempotency-Key': idempotencyKey},
    ),
  );

  @override
  Future<SubmitAck?> submissionStatus(
    String attemptId, {
    required String idempotencyKey,
  }) async {
    try {
      return SubmitAck.fromJson(
        await client.getJson(
          '$_p/attempts/${Uri.encodeComponent(attemptId)}/submission',
          query: {'idempotency_key': idempotencyKey},
        ),
      );
    } on PlatformException catch (e) {
      if (e.code == PlatformErrorCode.notFound) return null;
      rethrow;
    }
  }
}

/// Used when the platform is not configured and mocks are off: every call
/// fails with notConfigured, so nothing is shown as if it were real.
class UnavailableQuestionnaireApi implements QuestionnaireApi {
  const UnavailableQuestionnaireApi();

  static Never _no() =>
      throw const PlatformException(PlatformErrorCode.notConfigured);

  @override
  bool get isMock => false;
  @override
  Future<List<Assignment>> assignments() async => _no();
  @override
  Future<QuestionnaireVersion> version(String versionId) async => _no();
  @override
  Future<Attempt> attempt(String attemptId) async => _no();
  @override
  Future<DraftAck> saveDraft(
    String attemptId, {
    required int expectedRevision,
    required Map<String, Answer> answers,
    required String clientMutationId,
  }) async => _no();
  @override
  Future<Attempt> restart(
    String attemptId, {
    required int expectedRevision,
  }) async => _no();
  @override
  Future<SubmitAck> submit(
    String attemptId, {
    required String idempotencyKey,
    required int expectedRevision,
  }) async => _no();
  @override
  Future<SubmitAck?> submissionStatus(
    String attemptId, {
    required String idempotencyKey,
  }) async => _no();
}
