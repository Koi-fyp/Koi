import '../care/care_api_support.dart';
import '../platform/platform_client.dart';
import 'application_models.dart';

/// The consent version the web server accepts (WEB-2 semantics
/// "currently implemented `care-consent-v1`"; patient-types.ts:3).
const String careConsentVersion = 'care-consent-v1';

abstract interface class ApplicationApi {
  bool get isMock;
  Future<ApiPage<ConnectionRequest>> list({String? cursor});

  /// The server returns the EXISTING request for the same psychologist
  /// (its id is derived from applicant + practice), so a second create is
  /// never a duplicate.
  Future<ConnectionRequest> create(
    String psychologistUid, {
    required String idempotencyKey,
  });

  Future<ConnectionRequest> transition(
    String id, {
    required int expectedRevision,
    required ApplicationState to,
    required String idempotencyKey,
  });

  Future<ConnectionRequest> completeDemoPayment(
    String id, {
    required int expectedRevision,
    required String idempotencyKey,
  });
}

/// REAL on origin/feat/web-1-professional-publishing (f2b9c80, not on
/// main, not deployed): lifecycle-http.ts:30-32 → lifecycle.ts:147 / 173,
/// list lifecycle.ts:347. Mutations need a sign-in within 5 minutes
/// (service.ts:23), surfaced as [PlatformErrorCode.reauthRequired].
class HttpApplicationApi implements ApplicationApi {
  HttpApplicationApi(this.client);
  final PlatformClient client;

  static const String path = '/api/v1/connection-requests';

  @override
  bool get isMock => false;

  @override
  Future<ApiPage<ConnectionRequest>> list({String? cursor}) async =>
      parseApiPage(
        await client.getJson(path, query: pageQuery(cursor: cursor)),
        ConnectionRequest.fromJson,
      );

  @override
  Future<ConnectionRequest> create(
    String psychologistUid, {
    required String idempotencyKey,
  }) async => ConnectionRequest.fromJson(
    await client.sendJson('POST', path, {
      'psychologist_uid': psychologistUid,
      'consent_version': careConsentVersion,
    }, idempotencyKey: idempotencyKey),
  );

  @override
  Future<ConnectionRequest> transition(
    String id, {
    required int expectedRevision,
    required ApplicationState to,
    required String idempotencyKey,
  }) async => ConnectionRequest.fromJson(
    await client.sendJson(
      'POST',
      '$path/${Uri.encodeComponent(id)}/transition',
      {'expected_revision': expectedRevision, 'to_state': to.wire},
      idempotencyKey: idempotencyKey,
    ),
  );

  @override
  Future<ConnectionRequest> completeDemoPayment(
    String id, {
    required int expectedRevision,
    required String idempotencyKey,
  }) async => ConnectionRequest.fromJson(
    await client.sendJson(
      'POST',
      '$path/${Uri.encodeComponent(id)}/demo-payment',
      {'expected_revision': expectedRevision},
      idempotencyKey: idempotencyKey,
    ),
  );
}

class UnavailableApplicationApi implements ApplicationApi {
  const UnavailableApplicationApi();

  @override
  bool get isMock => false;
  @override
  Future<ApiPage<ConnectionRequest>> list({String? cursor}) =>
      careNotConfigured();
  @override
  Future<ConnectionRequest> create(
    String psychologistUid, {
    required String idempotencyKey,
  }) => careNotConfigured();
  @override
  Future<ConnectionRequest> transition(
    String id, {
    required int expectedRevision,
    required ApplicationState to,
    required String idempotencyKey,
  }) => careNotConfigured();
  @override
  Future<ConnectionRequest> completeDemoPayment(
    String id, {
    required int expectedRevision,
    required String idempotencyKey,
  }) => careNotConfigured();
}
