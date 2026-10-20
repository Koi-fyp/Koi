import '../care/care_api_support.dart';
import '../platform/platform_client.dart';
import 'message_models.dart';

abstract interface class CareMessageApi {
  bool get isMock;

  /// One page of a relationship's messages, in the server's document-id
  /// order (NOT by time: community.ts:188, semantics "displayed
  /// chronologically within loaded records"). The thread reads every page
  /// and sorts by `created_at` itself (CareList.loadAll).
  Future<ApiPage<HumanMessage>> list(String relationshipId, {String? cursor});

  Future<HumanMessage> send(
    String relationshipId,
    String body, {
    required String idempotencyKey,
  });
}

// REAL, contract v0.5.2 (origin/handoff/koi-web-1-to-5-2026-10-20, read
// with git show only; openapi x-status still says proposed_not_implemented
// but the routes exist): GET /api/v1/relationships/{id}/messages →
// community-http.ts:37 → community.ts:183-192; POST /api/v1/messages →
// community-http.ts:34 → community.ts:132-146 (201, active relationship,
// whitespace-only body 422, sign-in within 5 minutes → reauth).
class HttpCareMessageApi implements CareMessageApi {
  HttpCareMessageApi(this.client);
  final PlatformClient client;

  @override
  bool get isMock => false;

  @override
  Future<ApiPage<HumanMessage>> list(
    String relationshipId, {
    String? cursor,
  }) async => parseApiPage(
    await client.getJson(
      '/api/v1/relationships/${Uri.encodeComponent(relationshipId)}/messages',
      query: pageQuery(cursor: cursor, limit: carePageLimitAll),
    ),
    HumanMessage.fromJson,
  );

  @override
  Future<HumanMessage> send(
    String relationshipId,
    String body, {
    required String idempotencyKey,
  }) async => HumanMessage.fromJson(
    await client.sendJson('POST', '/api/v1/messages', {
      'relationship_id': relationshipId,
      'body': body,
    }, idempotencyKey: idempotencyKey),
  );
}

class UnavailableCareMessageApi implements CareMessageApi {
  const UnavailableCareMessageApi();

  @override
  bool get isMock => false;
  @override
  Future<ApiPage<HumanMessage>> list(String relationshipId, {String? cursor}) =>
      careNotConfigured();
  @override
  Future<HumanMessage> send(
    String relationshipId,
    String body, {
    required String idempotencyKey,
  }) => careNotConfigured();
}
