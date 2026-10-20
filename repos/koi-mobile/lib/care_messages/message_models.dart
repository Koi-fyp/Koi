import 'package:flutter/foundation.dart';

import '../care/care_api_support.dart';
import '../platform/platform_client.dart';

// Professional (human) messages with the psychologist. SEPARATE from the KOI
// companion chat: nothing in lib/care_messages imports lib/chat, lib/avatar,
// lib/voice*, lib/safety or lib/environment, and nothing here is ever sent
// to /api/v1/chat (tests MOB2-22).

/// Contract v0.5.2 `HumanMessageDTO`: exactly `{id, relationship_id,
/// sender_uid, body, created_at}`. No read receipt, no edit/delete.
@immutable
class HumanMessage {
  const HumanMessage({
    required this.id,
    required this.relationshipId,
    required this.senderUid,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String relationshipId;
  final String senderUid;
  final String body;
  final DateTime createdAt;

  factory HumanMessage.fromJson(Object? v) {
    final j = asJsonMap(v, 'message');
    final body = j['body'];
    if (body is! String || body.isEmpty) {
      throw const FormatException('Missing body');
    }
    return HumanMessage(
      id: reqString(j, 'id'),
      relationshipId: reqString(j, 'relationship_id'),
      senderUid: reqString(j, 'sender_uid'),
      body: body,
      createdAt: reqTime(j, 'created_at'),
    );
  }
}

/// Contract `CreateMessageRequest.body` maxLength.
const int humanMessageMaxLength = 4000;

/// A message typed on this phone that the server has not confirmed yet.
enum OutgoingStatus { pending, failed }

@immutable
class OutgoingMessage {
  const OutgoingMessage({
    required this.localId,
    required this.body,
    required this.idempotencyKey,
    required this.createdAt,
    this.status = OutgoingStatus.pending,
  });

  final String localId;
  final String body;

  /// Reused by "tap to retry", so a send that did land is not duplicated.
  final String idempotencyKey;
  final DateTime createdAt;
  final OutgoingStatus status;

  OutgoingMessage withStatus(OutgoingStatus s) => OutgoingMessage(
    localId: localId,
    body: body,
    idempotencyKey: idempotencyKey,
    createdAt: createdAt,
    status: s,
  );
}
