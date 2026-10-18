import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:koi_flutter_lib/services/crypto_service.dart';

import '../core/crypto_context.dart';
import '../core/emotion.dart';
import '../core/sync_queue.dart';
import 'chat_api.dart';
import 'chat_session_state.dart';
import 'message_record.dart';

/// conversationService.ts `SendMessageResult`.
@immutable
class SendMessageResult {
  const SendMessageResult({
    required this.reply,
    required this.emotion,
    required this.latencyMs,
    this.companionState,
    this.isFallback = false,
    this.failureCode,
  });
  final String reply;

  /// The label stored with the reply (web storedEmotion()).
  final Emotion emotion;
  final num? latencyMs;

  /// The backend's companion_state; null for the fallback reply.
  final CompanionState? companionState;

  /// The connection-trouble reply (never sent back as history).
  final bool isFallback;

  /// Why the fallback was used: an HTTP status, `timeout`, `network`,
  /// another [ChatApiException] code or an error type. Never a body.
  final String? failureCode;
}

/// Resolves the crypto context (crypto_context.dart, correct two-argument
/// form — Q4). Injectable for tests.
typedef CryptoContextGetter = Future<CryptoContext> Function(String uid);

/// Returns the Firebase ID token. Throws when there is no Firebase user (the
/// debug stand-in never has one), which takes the fallback path exactly like
/// web when `getAuth().currentUser` is null.
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

  /// Called at send time for every request; the token is never kept.
  final IdTokenGetter idToken;

  static bool _loggedNotConfigured = false;
  final DateTime Function() _now;
  final String Function() _newId;

  /// conversationService.ts fallback text and emotion.
  static const String fallbackReply =
      "I'm having a little trouble connecting right now. I'm still here with you.";
  static const Emotion fallbackEmotion = Emotion.calm;

  /// Firestore path users/{uid}/conversations/{conversationId}/messages
  /// (team decision 2026-10-17; firestore.rules.proposed has this match
  /// commented out, so these writes are rejected until it is enabled).
  /// Q5: conversationId = uid. NOTE: web writes
  /// conversations/{conversationId}/messages with a random uuidv4() id.
  static String messagesCollection(String uid, String conversationId) =>
      'users/$uid/conversations/$conversationId/messages';

  /// saveMessage(): encrypt → local store → enqueue the ENCRYPTED record only
  /// (priority 3). `timestamp` is written as a Firestore Timestamp.
  Future<void> saveMessage(MessageRecord record, String uid) async {
    final ctx = await cryptoContext(uid);
    final encrypted = record.copyWith(
      content: await cipher.encrypt(record.content, ctx.secret, ctx.saltB64),
    );
    await store.put(encrypted);
    syncQueue.enqueue(
      SyncItem(
        collection: messagesCollection(uid, record.conversationId),
        docId: record.id,
        data: encrypted.toJson(),
        priority: 3,
        timestampFields: const ['timestamp'],
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

  /// Whether KOI_API_BASE is set and valid.
  bool get isConfigured => api.isConfigured;

  /// sendMessage(): the user message is persisted BEFORE the AI call; on any
  /// failure the fallback reply is saved and returned, so chat never breaks.
  ///
  /// [session] supplies exercise_state / client_event / crisis_path and is
  /// updated only after a successful stream; [onResolutionSent] runs when
  /// that stream carried a crisis path. Risk comes only from the chat
  /// stream's `risk` event (C8 decided 2026-10-18: no /api/v1/crisis call).
  ///
  /// [beforeRequest] runs after the user message is saved and before the
  /// token is fetched and the request sent (BackendWarmup.holdFirstSend).
  Future<SendMessageResult> sendMessage({
    required String userId,
    required String conversationId,
    required String text,
    required List<ChatTurn> context,
    ChatHandlers handlers = const ChatHandlers(),
    ChatSessionState? session,
    VoidCallback? onResolutionSent,
    Future<void> Function()? beforeRequest,
  }) async {
    await saveMessage(
      _record(conversationId, 'user', text, Emotion.neutral),
      userId,
    );

    final state = session ?? ChatSessionState();
    try {
      if (!api.isConfigured) {
        if (kDebugMode && !_loggedNotConfigured) {
          _loggedNotConfigured = true;
          debugPrint('[KOI] chat: not configured');
        }
        throw const ChatApiException(ChatApiException.notConfigured);
      }
      await beforeRequest?.call();
      final token = await idToken();
      final turn = state.beginTurn();
      final r = await api.streamChat(
        idToken: token,
        body: state.requestBody(turn, message: text, sessionHistory: context),
        handlers: handlers,
      );
      if (r.fullText.trim().isEmpty) {
        // web parseChatResponse(): an empty reply is invalid.
        throw const ChatApiException(ChatApiException.emptyReply);
      }
      if (state.turnSucceeded(turn, r)) onResolutionSent?.call();
      // The full, untrimmed reply.
      await saveMessage(
        _record(conversationId, 'ai', r.fullText, r.emotion),
        userId,
      );
      return SendMessageResult(
        reply: r.fullText,
        emotion: r.emotion,
        latencyMs: r.latencyMs,
        companionState: r.companionState,
      );
    } catch (e) {
      // Error code / type only; never message content or a token.
      final code = e is ChatApiException
          ? e.code
          : e is ChatTimeoutException
          ? 'timeout'
          : e.runtimeType.toString();
      debugPrint('[KOI] sendMessage failed: $code');
      await saveMessage(
        _record(conversationId, 'ai', fallbackReply, fallbackEmotion),
        userId,
      );
      return SendMessageResult(
        reply: fallbackReply,
        emotion: fallbackEmotion,
        latencyMs: null,
        isFallback: true,
        failureCode: code,
      );
    }
  }
}
