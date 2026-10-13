import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:koi_flutter_lib/services/crypto_service.dart';

import '../core/crypto_context.dart';
import '../core/emotion.dart';
import '../core/sync_queue.dart';
import 'chat_api.dart';
import 'message_record.dart';

/// conversationService.ts `SendMessageResult`.
@immutable
class SendMessageResult {
  const SendMessageResult({
    required this.reply,
    required this.emotion,
    required this.latencyMs,
  });
  final String reply;
  final Emotion emotion;
  final num? latencyMs;
}

/// Resolves the crypto context (crypto_context.dart, correct two-argument
/// form — Q4). Injectable for tests.
typedef CryptoContextGetter = Future<CryptoContext> Function(String uid);

/// Returns the Firebase ID token. TODO(Q1, firebase): the debug stand-in has
/// no Firebase user, so this throws, which takes the fallback path exactly
/// like web when `getAuth().currentUser` is null.
typedef IdTokenGetter = Future<String> Function();

/// Encrypts/decrypts with flutter_lib's KoiCryptoService (format
/// v1:PBKDF2:salt:nonce:ct). Injectable for tests.
abstract class MessageCipher {
  Future<String> encrypt(String plaintext, String secret, String saltB64);
  Future<String> decrypt(String payload, String secret);
}

class KoiMessageCipher implements MessageCipher {
  KoiMessageCipher([KoiCryptoService? service])
    : _service = service ?? KoiCryptoService();
  final KoiCryptoService _service;

  @override
  Future<String> encrypt(String plaintext, String secret, String saltB64) =>
      _service.encrypt(plaintext, secret, saltB64);
  @override
  Future<String> decrypt(String payload, String secret) =>
      _service.decrypt(payload, secret);
}

/// Random v4 UUID (web: uuid's v4()).
String uuidV4([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

/// Mirrors repos/koi-backend/nextjs_app/src/lib/conversation/
/// conversationService.ts: saveMessage() and sendMessage().
///
/// Never logs message content (plaintext or ciphertext).
class ConversationService {
  ConversationService({
    required this.cryptoContext,
    required this.cipher,
    required this.store,
    required this.syncQueue,
    required this.api,
    required this.idToken,
    DateTime Function()? now,
    String Function()? newId,
  }) : _now = now ?? DateTime.now,
       _newId = newId ?? uuidV4;

  final CryptoContextGetter cryptoContext;
  final MessageCipher cipher;
  final MessageStore store;
  final SyncQueue syncQueue;
  final ChatApiClient api;
  final IdTokenGetter idToken;
  final DateTime Function() _now;
  final String Function() _newId;

  /// conversationService.ts fallback text and emotion.
  static const String fallbackReply =
      "I'm having a little trouble connecting right now. I'm still here with you.";
  static const Emotion fallbackEmotion = Emotion.calm;

  /// Firestore path. Q5 (decided 2026-10-13): mobile uses
  /// conversationId = uid, because firestore.rules only allow
  /// conversations/{userId}/messages/... where the id equals the user's uid.
  /// NOTE: web's useChat uses a random uuidv4() conversationId, which those
  /// rules would reject.
  static String messagesCollection(String conversationId) =>
      'conversations/$conversationId/messages';

  /// saveMessage(): encrypt → local store → enqueue the ENCRYPTED record only
  /// (priority 3).
  Future<void> saveMessage(MessageRecord record, String uid) async {
    final ctx = await cryptoContext(uid);
    final encrypted = record.copyWith(
      content: await cipher.encrypt(record.content, ctx.secret, ctx.saltB64),
    );
    await store.put(encrypted);
    // TODO(firebase): when the cloud_firestore writer exists, convert the
    // ISO timestamp to a Firestore Timestamp like web's Date field.
    syncQueue.enqueue(
      SyncItem(
        collection: messagesCollection(record.conversationId),
        docId: record.id,
        data: encrypted.toJson(),
        priority: 3,
      ),
    );
  }

  MessageRecord _record(
    String conversationId,
    String sender,
    String content,
    Emotion emotion,
  ) => MessageRecord(
    id: _newId(),
    conversationId: conversationId,
    sender: sender,
    content: content,
    timestamp: _now(),
    emotion: emotion,
    emotionConfidence: 1,
    synced: false,
  );

  /// sendMessage(): the user message is persisted BEFORE the AI call; on any
  /// failure the fallback reply is saved and returned.
  Future<SendMessageResult> sendMessage({
    required String userId,
    required String conversationId,
    required String text,
    required List<ChatTurn> context,
    void Function(String chunk)? onDelta,
  }) async {
    await saveMessage(
      _record(conversationId, 'user', text, Emotion.neutral),
      userId,
    );

    try {
      final token = await idToken();
      final r = await api.streamChat(
        idToken: token,
        message: text,
        sessionHistory: context,
        onDelta: onDelta,
      );
      await saveMessage(
        _record(conversationId, 'ai', r.fullText, r.emotion),
        userId,
      );
      return SendMessageResult(
        reply: r.fullText,
        emotion: r.emotion,
        latencyMs: r.latencyMs,
      );
    } catch (e) {
      // Error type only; never message content.
      debugPrint('[KOI] sendMessage failed: ${e.runtimeType}');
      await saveMessage(
        _record(conversationId, 'ai', fallbackReply, fallbackEmotion),
        userId,
      );
      return const SendMessageResult(
        reply: fallbackReply,
        emotion: fallbackEmotion,
        latencyMs: null,
      );
    }
  }
}
