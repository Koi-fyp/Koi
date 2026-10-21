import 'package:cloud_firestore/cloud_firestore.dart';

import '../sync_queue.dart';
import 'firestore_remote_writer.dart' show firestoreData;

/// A Dart MIRROR of the live Firestore rules (published 2026-10-20). It
/// only ever rejects what the rules would reject, before the write is sent,
/// so a write that can never succeed is not retried. It must never be
/// weaker than the rules, and it never replaces them.
///
/// The rules allow writes to exactly two places:
/// - users/{uid}: get / create / update by its owner (any fields);
/// - users/{uid}/conversations/{cid}/messages/{mid}: create with exactly
///   [liveMessageKeys] ([liveMessageViolation]); update only if identical.
/// Everything else is denied.

/// The message key set: all of them, nothing else.
const Set<String> liveMessageKeys = {
  'id',
  'conversationId',
  'sender',
  'content',
  'timestamp',
  'emotion',
  'emotion_confidence',
  'synced',
};

const Set<String> liveMessageSenders = {'user', 'ai'};

/// `v1:PBKDF2:base64(salt16):base64(nonce12):base64(ct+tag)`.
final RegExp liveCiphertextPattern = RegExp(
  r'^v1:PBKDF2:[A-Za-z0-9+/]{22}==:[A-Za-z0-9+/]{16}:[A-Za-z0-9+/]{22,}={0,2}$',
);

const int liveCiphertextMaxLength = 65536;
const int liveEmotionMaxLength = 32;

/// `timestamp <= request.time + 5 min`.
const Duration liveTimestampSkew = Duration(minutes: 5);

final RegExp _messagesPath = RegExp(
  r'^users/([^/]+)/conversations/([^/]+)/messages$',
);

/// Why [item] would be denied by the live rules, or null when it would be
/// allowed. [now] stands in for `request.time` (the device clock). The
/// reason is a short code, never data.
String? liveRulesViolation(SyncItem item, {DateTime? now}) {
  if (item.collection == 'users') return null;
  final m = _messagesPath.firstMatch(item.collection);
  if (m == null) return 'path';
  return liveMessageViolation(
    firestoreData(item),
    cid: m.group(2)!,
    mid: item.docId,
    now: now ?? DateTime.now(),
  );
}

/// The rules' `messageOk(d)` for messages/{mid} under conversations/{cid}.
String? liveMessageViolation(
  Map<String, Object?> d, {
  required String cid,
  required String mid,
  required DateTime now,
}) {
  final keys = d.keys.toSet();
  if (keys.length != liveMessageKeys.length ||
      !keys.containsAll(liveMessageKeys)) {
    return 'keys';
  }
  if (d['id'] is! String || d['id'] != mid) return 'id';
  if (d['conversationId'] is! String || d['conversationId'] != cid) {
    return 'conversationId';
  }
  if (!liveMessageSenders.contains(d['sender'])) return 'sender';
  final content = d['content'];
  if (content is! String ||
      content.length > liveCiphertextMaxLength ||
      !liveCiphertextPattern.hasMatch(content)) {
    return 'content';
  }
  final ts = d['timestamp'];
  if (ts is! Timestamp || ts.toDate().isAfter(now.add(liveTimestampSkew))) {
    return 'timestamp';
  }
  final emotion = d['emotion'];
  if (emotion is! String || emotion.length > liveEmotionMaxLength) {
    return 'emotion';
  }
  final confidence = d['emotion_confidence'];
  if (confidence is! num || !(confidence >= 0 && confidence <= 1)) {
    return 'emotion_confidence';
  }
  if (d['synced'] is! bool) return 'synced';
  return null;
}
