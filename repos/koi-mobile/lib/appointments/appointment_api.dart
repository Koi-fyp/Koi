import '../care/care_api_support.dart';
import '../platform/platform_client.dart';
import 'appointment_models.dart';

abstract interface class AppointmentApi {
  bool get isMock;
  Future<ApiPage<Appointment>> list(String relationshipId, {String? cursor});

  /// The contract's request carries ONLY the relationship: no time, no note.
  Future<Appointment> request(
    String relationshipId, {
    required String idempotencyKey,
  });

  /// The patient only ever sends `confirmed` (of a proposal) or `cancelled`.
  Future<Appointment> transition(
    String id, {
    required int expectedRevision,
    required AppointmentState to,
    required String idempotencyKey,
  });
}

// REAL, contract v0.5.2 (origin/handoff/koi-web-1-to-5-2026-10-20, read
// with git show only; openapi x-status is stale): list → community.ts:183
// (document-id order, read in full by CareList.loadAll); create
// {relationship_id} → community.ts:160-162 (patient only, 201);
// transition {expected_revision, to_state} → community.ts:163-176 (stale
// revision or illegal move 409; a patient never sends starts_at/ends_at).
// Mutations need a sign-in within 5 minutes (service.ts:23).
class HttpAppointmentApi implements AppointmentApi {
  HttpAppointmentApi(this.client);
  final PlatformClient client;

  @override
  bool get isMock => false;

  @override
  Future<ApiPage<Appointment>> list(
    String relationshipId, {
    String? cursor,
  }) async => parseApiPage(
    await client.getJson(
      '/api/v1/relationships/${Uri.encodeComponent(relationshipId)}'
      '/appointments',
      query: pageQuery(cursor: cursor, limit: carePageLimitAll),
    ),
    Appointment.fromJson,
  );

  @override
  Future<Appointment> request(
    String relationshipId, {
    required String idempotencyKey,
  }) async => Appointment.fromJson(
    await client.sendJson('POST', '/api/v1/appointments', {
      'relationship_id': relationshipId,
    }, idempotencyKey: idempotencyKey),
  );

  @override
  Future<Appointment> transition(
    String id, {
    required int expectedRevision,
    required AppointmentState to,
    required String idempotencyKey,
  }) async => Appointment.fromJson(
    await client.sendJson(
      'POST',
      '/api/v1/appointments/${Uri.encodeComponent(id)}/transition',
      {'expected_revision': expectedRevision, 'to_state': to.wire},
      idempotencyKey: idempotencyKey,
    ),
  );
}

class UnavailableAppointmentApi implements AppointmentApi {
  const UnavailableAppointmentApi();

  @override
  bool get isMock => false;
  @override
  Future<ApiPage<Appointment>> list(String relationshipId, {String? cursor}) =>
      careNotConfigured();
  @override
  Future<Appointment> request(
    String relationshipId, {
    required String idempotencyKey,
  }) => careNotConfigured();
  @override
  Future<Appointment> transition(
    String id, {
    required int expectedRevision,
    required AppointmentState to,
    required String idempotencyKey,
  }) => careNotConfigured();
}
