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

// REAL, contract v0.5.2 (origin/handoff/koi-web-1-to-5-2026-10-20, read
// with git show only; openapi x-status is stale): GET /api/v1/notifications
// → community.ts:193-215 (registered accounts only; the first page also
// delivers missing assignment notices; closed relationships are left out);
// POST /api/v1/notifications/{id}/read with body {} → community.ts:199-205
// (no recent sign-in needed; the first read_at is kept). Unread counts
// describe loaded notifications only (semantics.md).
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
