import 'package:flutter/foundation.dart';

import '../care/care_api_support.dart';
import '../platform/platform_client.dart';

/// Contract v0.5.1 `NotificationDTO.kind`: exactly four fixed kinds with
/// typed id references and NO text (semantics: "No arbitrary
/// title/body/data/provider strings, evaluation events or AI progress").
/// The app writes its own fixed wording per kind. Any other kind is
/// ignored safely.
enum NotificationKind {
  assignment('assignment', 'assignment_id'),
  newMessage('new_message', 'message_id'),
  appointmentChange('appointment_change', 'appointment_id'),
  applicationState('application_state', 'connection_request_id');

  const NotificationKind(this.wire, this.referenceKey);
  final String wire;
  final String referenceKey;

  static NotificationKind? fromWire(Object? v) {
    for (final k in values) {
      if (k.wire == v) return k;
    }
    return null;
  }
}

@immutable
class CareNotification {
  const CareNotification({
    required this.id,
    required this.eventId,
    required this.kind,
    required this.referenceId,
    required this.createdAt,
    this.readAt,
  });

  final String id;

  /// Stable event id: repeated deliveries of one event are shown once.
  final String eventId;
  final NotificationKind kind;

  /// The one id of [NotificationKind.referenceKey]. Nothing else from the
  /// reference object is read.
  final String referenceId;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  CareNotification markedRead(DateTime at) => CareNotification(
    id: id,
    eventId: eventId,
    kind: kind,
    referenceId: referenceId,
    createdAt: createdAt,
    readAt: at,
  );

  /// Returns null for an unknown kind (ignored safely).
  static CareNotification? fromJson(Object? v) {
    final j = asJsonMap(v, 'notification');
    final kind = NotificationKind.fromWire(j['kind']);
    if (kind == null) return null;
    final ref = asJsonMap(j['reference'], 'reference');
    return CareNotification(
      id: reqString(j, 'id'),
      eventId: reqString(j, 'event_id'),
      kind: kind,
      referenceId: reqString(ref, kind.referenceKey),
      createdAt: reqTime(j, 'created_at'),
      readAt: optTime(j, 'read_at'),
    );
  }
}
