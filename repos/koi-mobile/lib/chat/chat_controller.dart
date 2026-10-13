import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/emotion.dart';
import 'chat_api.dart';
import 'conversation_service.dart';
import 'message_record.dart';

/// useChat.ts `ChatMessage` (plaintext, in memory only).
@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.sender,
    required this.content,
    required this.timestamp,
    required this.emotion,
  });

  final String id;
  final String conversationId;

  /// 'user' | 'ai'
  final String sender;
  final String content;
  final DateTime timestamp;
  final Emotion emotion;

  bool get isUser => sender == 'user';
}

/// Mirrors repos/koi-backend/nextjs_app/src/hooks/useChat.ts.
///
/// Differences, on purpose:
/// - conversationId = uid (Q5), so history persists across launches (web
///   makes a new random id on every mount, so its history is always empty).
/// - Context = the real last 5 messages before the new one. Web intends
///   this, but its `send` is a useCallback with [] deps, so it always reads
///   the initial empty `messages` and sends no context (web bug, not copied).
/// - Crypto context uses the correct two-argument form (Q4).
class ChatController extends ChangeNotifier {
  ChatController({
    required this.uid,
    required this.service,
    required this.isOnline,
    Stream<bool>? onlineChanges,
    DateTime Function()? now,
    String Function()? newId,
  }) : _now = now ?? DateTime.now,
       _newId = newId ?? uuidV4 {
    // window.addEventListener('online', flush)
    _sub = onlineChanges?.where((o) => o).listen((_) => _flush());
  }

  final String uid;
  final ConversationService service;
  final Future<bool> Function() isOnline;
  final DateTime Function() _now;
  final String Function() _newId;
  StreamSubscription<bool>? _sub;

  final List<ChatMessage> _messages = [];
  bool _isTyping = false;
  Emotion _currentEmotion = Emotion.neutral;
  final List<Future<void> Function()> _offlineQueue = [];
  bool _disposed = false;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isTyping => _isTyping;
  Emotion get currentEmotion => _currentEmotion;

  /// Q5: conversationId = uid.
  String get conversationId => uid;

  /// Number of turns sent as context (useChat: `messages.slice(-5)`).
  static const int contextTurns = 5;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// useChat's mount effect: load this conversation's stored messages and
  /// decrypt them; a message that fails to decrypt is shown raw (web).
  Future<void> loadHistory() async {
    try {
      final rows = await service.store.byConversation(conversationId);
      if (rows.isEmpty) return;
      final ctx = await service.cryptoContext(uid);
      final loaded = <ChatMessage>[];
      for (final r in rows) {
        var content = r.content;
        try {
          content = await service.cipher.decrypt(r.content, ctx.secret);
        } catch (_) {
          debugPrint(
            '[KOI] Failed to decrypt message, showing raw content: '
            '${r.id}',
          );
        }
        loaded.add(_fromRecord(r, content));
      }
      _messages
        ..clear()
        ..addAll(loaded);
      _notify();
    } catch (_) {
      // web: .catch(() => {})
    }
  }

  ChatMessage _fromRecord(MessageRecord r, String content) => ChatMessage(
    id: r.id,
    conversationId: r.conversationId,
    sender: r.sender,
    content: content,
    timestamp: r.timestamp,
    emotion: r.emotion,
  );

  Future<void> _flush() async {
    final tasks = List.of(_offlineQueue);
    _offlineQueue.clear();
    for (final task in tasks) {
      try {
        await task();
      } catch (_) {
        // keep going
      }
    }
  }

  /// Derives the session key once in the background (native PBKDF2 +
  /// session cache, see core/koi_cryptography.dart) so the first send is not
  /// delayed. Failures are ignored; saveMessage will surface them.
  Future<void> warmUpKey() async {
    try {
      final ctx = await service.cryptoContext(uid);
      await service.cipher.encrypt('', ctx.secret, ctx.saltB64);
    } catch (_) {}
  }

  @visibleForTesting
  int get offlineQueueLength => _offlineQueue.length;

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    // Context is taken BEFORE the new message is added.
    final start = _messages.length > contextTurns
        ? _messages.length - contextTurns
        : 0;
    final context = [
      for (final m in _messages.sublist(start))
        ChatTurn(
          role: m.isUser ? historyRoleUser : historyRoleAi,
          content: m.content,
        ),
    ];

    _messages.add(
      ChatMessage(
        id: _newId(),
        conversationId: conversationId,
        sender: 'user',
        content: trimmed,
        timestamp: _now(),
        emotion: Emotion.neutral,
      ),
    );
    _isTyping = true;
    _notify();

    Future<void> doSend() async {
      try {
        final result = await service.sendMessage(
          userId: uid,
          conversationId: conversationId,
          text: trimmed,
          context: context,
        );
        _currentEmotion = result.emotion;
        _messages.add(
          ChatMessage(
            id: _newId(),
            conversationId: conversationId,
            sender: 'ai',
            content: result.reply,
            timestamp: _now(),
            emotion: result.emotion,
          ),
        );
      } finally {
        _isTyping = false;
        _notify();
      }
    }

    if (!await isOnline()) {
      _offlineQueue.add(doSend);
      _isTyping = false;
      _notify();
    } else {
      await doSend();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}
