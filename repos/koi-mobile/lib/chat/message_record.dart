import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/emotion.dart';

/// Web's `MessageRecord` (repos/koi-backend/nextjs_app/src/lib/db.ts), with
/// the same field names. `content` is always the ENCRYPTED payload once
/// saved. sentiment_score / crisis_flag are deliberately absent, as in
/// conversationService.ts ("left undefined until TSD supplies them").
@immutable
class MessageRecord {
  const MessageRecord({
    required this.id,
    required this.conversationId,
    required this.sender,
    required this.content,
    required this.timestamp,
    required this.emotion,
    required this.emotionConfidence,
    required this.synced,
  });

  final String id;
  final String conversationId;

  /// 'user' | 'ai'
  final String sender;
  final String content;
  final DateTime timestamp;
  final Emotion emotion;
  final num emotionConfidence;
  final bool synced;

  MessageRecord copyWith({String? content}) => MessageRecord(
    id: id,
    conversationId: conversationId,
    sender: sender,
    content: content ?? this.content,
    timestamp: timestamp,
    emotion: emotion,
    emotionConfidence: emotionConfidence,
    synced: synced,
  );

  /// JSON with web's field names. The timestamp is an ISO-8601 string, which
  /// is also what web's sync.ts ends up queueing (JSON.stringify of a Date).
  Map<String, Object?> toJson() => {
    'id': id,
    'conversationId': conversationId,
    'sender': sender,
    'content': content,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'emotion': emotion.wire,
    'emotion_confidence': emotionConfidence,
    'synced': synced,
  };

  factory MessageRecord.fromJson(Map<String, Object?> j) => MessageRecord(
    id: j['id']! as String,
    conversationId: j['conversationId']! as String,
    sender: j['sender']! as String,
    content: j['content']! as String,
    timestamp: DateTime.parse(j['timestamp']! as String),
    emotion: Emotion.fromWire(j['emotion']),
    emotionConfidence: (j['emotion_confidence'] as num?) ?? 1,
    synced: (j['synced'] as bool?) ?? false,
  );
}

/// Local message table (web: Dexie `db.messages`).
abstract class MessageStore {
  Future<void> put(MessageRecord record);
  Future<List<MessageRecord>> byConversation(String conversationId);
}

/// Q9 (decided 2026-10-13): a koi-mobile Hive box, because flutter_lib's
/// HiveMessage has no `emotion` label or `emotion_confidence`. Records are
/// JSON strings keyed by id; `content` is already CSE-encrypted, so the box
/// itself is a plain one (web's IndexedDB is unencrypted too).
class HiveMessageStore implements MessageStore {
  HiveMessageStore(this._box);

  static const String boxName = 'koi_messages';
  final Box<String> _box;

  static Future<HiveMessageStore> open() async =>
      HiveMessageStore(await Hive.openBox<String>(boxName));

  @override
  Future<void> put(MessageRecord record) =>
      _box.put(record.id, jsonEncode(record.toJson()));

  /// web: `.where('conversationId').equals(id).sortBy('timestamp')`
  @override
  Future<List<MessageRecord>> byConversation(String conversationId) async {
    final rows = <MessageRecord>[];
    for (final raw in _box.values) {
      try {
        final r = MessageRecord.fromJson(
          (jsonDecode(raw) as Map).cast<String, Object?>(),
        );
        if (r.conversationId == conversationId) rows.add(r);
      } catch (_) {
        // A malformed row is skipped, never shown.
      }
    }
    rows.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return rows;
  }
}

/// In-memory store for tests.
class MemoryMessageStore implements MessageStore {
  final Map<String, MessageRecord> rows = {};

  @override
  Future<void> put(MessageRecord record) async => rows[record.id] = record;

  @override
  Future<List<MessageRecord>> byConversation(String conversationId) async =>
      rows.values.where((r) => r.conversationId == conversationId).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
}
