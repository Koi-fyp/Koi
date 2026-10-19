import '../care/care_api_support.dart';
import '../platform/platform_client.dart';
import 'message_models.dart';

abstract interface class CareMessageApi {
  bool get isMock;

  /// One page of a relationship's messages. The contract does not state
  /// the order; mobile sorts by `created_at` itself and treats the cursor
  /// as "older messages" (assumption, KOI_MOB1_PROVISIONAL_CONTRACTS.md §9).
  Future<ApiPage<HumanMessage>> list(String relationshipId, {String? cursor});

  Future<HumanMessage> send(
    String relationshipId,
    String body, {
    required String idempotencyKey,
  });
}

// PROVISIONAL CONTRACT: KOI_MOB1_PROVISIONAL_CONTRACTS.md §9 (Professional
// messages). Contract v0.5.1 createHumanMessage / listHumanMessages are
// `proposed_not_implemented`.
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
      query: pageQuery(cursor: cursor),
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
