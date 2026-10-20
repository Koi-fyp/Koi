import '../platform/platform_client.dart';
import 'questionnaire_models.dart';
import 'questionnaire_wire.dart';

/// The patient's questionnaire endpoints. Paths and flow are REAL contract
/// v0.5.1 (`listPatientAssignments`, `getPatientAssignment`,
/// `autosavePatientAttempt`, `submitPatientAttempt`; `web2_implemented`,
/// not deployed). The questionnaire body and answer items inside them are
/// // PROVISIONAL CONTRACT (KOI_MOB1_PROVISIONAL_CONTRACTS.md §3; see
/// questionnaire_wire.dart).
///
/// Every call carries the Firebase ID token; the server decides what this
/// uid may see. The app never calls psychologist-only or AI endpoints and
/// never holds an AI service URL.
abstract interface class QuestionnaireApi {
  /// Demo data (KOI_MOCKS): the screens show the "Demo data" badge.
  bool get isMock;

  Future<AssignmentPage> assignments({String? cursor});

  /// The open form (questionnaire + attempt) or, once submitted, only the
  /// acknowledgement.
  Future<AssignmentDetail> detail(String assignmentId);

  /// PATCH with the revision last seen (compare-and-set). A Restart is an
  /// autosave with no answers. A retry of the SAME save reuses
  /// [idempotencyKey]. 409 `conflict` when the server is newer or the
  /// attempt is already submitted.
  Future<AutosaveAck> autosave(
    String attemptId, {
    required int expectedRevision,
    required List<Answer> answers,
    required String idempotencyKey,
  });

  /// The ONLY way to submit. Same [idempotencyKey] = same submission. Needs
  /// a recent sign-in (401 `unauthenticated` → reauthRequired).
  Future<SubmitAck> submit(
    String attemptId, {
    required int expectedRevision,
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
  Future<AssignmentPage> assignments({String? cursor}) async =>
      parseAssignmentPage(
        await client.getJson(
          '$_p/assignments',
          query: {'limit': '100', 'cursor': ?cursor},
        ),
      );

  @override
  Future<AssignmentDetail> detail(String assignmentId) async =>
      parseAssignmentDetail(
        await client.getJson(
          '$_p/assignments/${Uri.encodeComponent(assignmentId)}',
        ),
      );

  @override
  Future<AutosaveAck> autosave(
    String attemptId, {
    required int expectedRevision,
    required List<Answer> answers,
    required String idempotencyKey,
  }) async => parseAutosaveAck(
    await client.sendJson(
      'PATCH',
      '$_p/attempts/${Uri.encodeComponent(attemptId)}',
      encodeAutosave(expectedRevision, answers),
      idempotencyKey: idempotencyKey,
    ),
  );

  @override
  Future<SubmitAck> submit(
    String attemptId, {
    required int expectedRevision,
    required String idempotencyKey,
  }) async => parseSubmitAck(
    await client.sendJson(
      'POST',
      '$_p/attempts/${Uri.encodeComponent(attemptId)}/submit',
      encodeSubmit(expectedRevision),
      idempotencyKey: idempotencyKey,
    ),
  );
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
  Future<AssignmentPage> assignments({String? cursor}) async => _no();
  @override
  Future<AssignmentDetail> detail(String assignmentId) async => _no();
  @override
  Future<AutosaveAck> autosave(
    String attemptId, {
    required int expectedRevision,
    required List<Answer> answers,
    required String idempotencyKey,
  }) async => _no();
  @override
  Future<SubmitAck> submit(
    String attemptId, {
    required int expectedRevision,
    required String idempotencyKey,
  }) async => _no();
}
