import '../care/care_api_support.dart';
import '../platform/platform_client.dart';
import 'notification_models.dart';

/// In-app inbox only: no FCM, no push permission (KOI_MOBILE_TRACK §8).
abstract interface class NotificationApi {
  bool get isMock;
  Future<ApiPage<CareNotification>> list({String? cursor});

  /// There is no mark-all endpoint: "mark all" calls this per item
  /// (decision C).
  Future<CareNotification> markRead(
    String id, {
    required String idempotencyKey,
  });
}

// PROVISIONAL CONTRACT: KOI_MOB1_PROVISIONAL_CONTRACTS.md §11
// (Notifications). Contract v0.5.1 listNotifications /
// markNotificationRead are `proposed_not_implemented`.
class HttpNotificationApi implements NotificationApi {
  HttpNotificationApi(this.client);
  final PlatformClient client;

  @override
  bool get isMock => false;

  @override
  Future<ApiPage<CareNotification>> list({String? cursor}) async =>
      parseApiPage(
        await client.getJson(
          '/api/v1/notifications',
          query: pageQuery(cursor: cursor),
        ),
        CareNotification.fromJson,
      );

  @override
  Future<CareNotification> markRead(
    String id, {
    required String idempotencyKey,
  }) async {
    final n = CareNotification.fromJson(
      await client.sendJson(
        'POST',
        '/api/v1/notifications/${Uri.encodeComponent(id)}/read',
        const {},
        idempotencyKey: idempotencyKey,
      ),
    );
    if (n == null) throw const FormatException('Unknown kind');
    return n;
  }
}

class UnavailableNotificationApi implements NotificationApi {
  const UnavailableNotificationApi();

  @override
  bool get isMock => false;
  @override
  Future<ApiPage<CareNotification>> list({String? cursor}) =>
      careNotConfigured();
  @override
  Future<CareNotification> markRead(
    String id, {
    required String idempotencyKey,
  }) => careNotConfigured();
}
