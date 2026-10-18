import 'dart:async';

import 'package:flutter/foundation.dart';

import '../avatar/avatar_state.dart';
import '../core/emotion.dart';
import '../safety/safety_contract.dart' show UiAction;
import '../safety/safety_controller.dart';
import 'backend_warmup.dart';
import 'chat_api.dart';
import 'chat_session_state.dart';
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

  /// The saved connection-trouble reply. It is shown, but never sent back
  /// as session_history (it did not come from the model).
  bool get isFallback =>
      !isUser && content == ConversationService.fallbackReply;

  ChatMessage withContent(String text) => ChatMessage(
    id: id,
    conversationId: conversationId,
    sender: sender,
    content: text,
    timestamp: timestamp,
    emotion: emotion,
  );
}

/// Mirrors repos/koi-backend/nextjs_app/src/hooks/useChat.ts, wired to the
/// streaming chat service (contract v1.1 C).
///
/// Differences, on purpose:
/// - conversationId = uid (Q5), so history persists across launches (web
///   makes a new random id on every mount, so its history is always empty).
/// - Context = the real last 5 messages before the new one, minus saved
///   fallback replies. Web intends this, but its `send` is a useCallback
///   with [] deps, so it always reads the initial empty `messages` and sends
///   no context (web bug, not copied).
/// - Crypto context uses the correct two-argument form (Q4).
/// - One message at a time: [send] does nothing while a reply is pending.
///
/// Stream events: deltas fill a live AI bubble (the last of [messages])
/// that becomes the saved message at `done`; companion_state and the
/// thinking / speaking / idle state go to [avatarEvents]; ui_action, handoff
/// and risk go to [safety].
class ChatController extends ChangeNotifier {
  ChatController({
    required this.uid,
    required this.service,
    required this.isOnline,
    Stream<bool>? onlineChanges,
    this.safety,
    ChatSessionState? session,
    this.backend,
    DateTime Function()? now,
    String Function()? newId,
  }) : session = session ?? ChatSessionState(),
       _now = now ?? DateTime.now,
       _newId = newId ?? uuidV4 {
    // window.addEventListener('online', flush)
    _sub = onlineChanges?.where((o) => o).listen((_) => _flush());
    backend?.addListener(_notify);
  }

  final String uid;
  final ConversationService service;
  final Future<bool> Function() isOnline;
  final SafetyController? safety;
  final ChatSessionState session;
  final BackendWarmup? backend;
  final DateTime Function() _now;
  final String Function() _newId;
  StreamSubscription<bool>? _sub;

  final List<ChatMessage> _messages = [];
  ChatMessage? _live;
  bool _isTyping = false;
  Emotion _currentEmotion = Emotion.neutral;
  CompanionState _companion = CompanionState.fallback;
  final List<Future<void> Function()> _offlineQueue = [];
  final _avatar = StreamController<AvatarStateEvent>.broadcast();
  bool _disposed = false;
  int _textOnlyEvents = 0;
  int _exerciseStarts = 0;

  /// The stored messages, then the live AI bubble while a reply streams.
  List<ChatMessage> get messages => List.unmodifiable([..._messages, ?_live]);

  bool get isTyping => _isTyping;

  /// Counts the stream events that keep a reply text only (Prompt 29, web
  /// useSpokenReplies.ts turnBlocksVoice): any handoff, a HIGH / CRITICAL
  /// risk result and any exercise ui_action. The call screen compares it
  /// across a turn.
  int get textOnlyEvents => _textOnlyEvents;

  /// Counts exercise starts (start_breathing / start_grounding /
  /// start_plan); the call screen discards a recording on each.
  int get exerciseStarts => _exerciseStarts;

  /// True once reply text is streaming into the live bubble.
  bool get isStreaming => _live != null;
  Emotion get currentEmotion => _currentEmotion;

  /// The latest companion_state from the backend.
  CompanionState get companionState => _companion;

  BackendStatus get backendStatus => backend?.status ?? BackendStatus.unknown;

  /// An audio turn waits for chat + crisis /health (show the waking line).
  bool get holdingAudio => backend?.holdingAudio ?? false;

  /// Avatar updates for [conversationId]: companion_state emotion and the
  /// thinking / speaking / idle state. Lip-sync is not connected.
  Stream<AvatarStateEvent> get avatarEvents => _avatar.stream;

  /// Q5: conversationId = uid.
  String get conversationId => uid;

  /// Number of turns sent as context (useChat: `messages.slice(-5)`).
  static const int contextTurns = 5;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _avatarState({
    AvatarEmotion? emotion,
    double intensity = 0,
    AvatarConversationState? state,
  }) {
    if (_avatar.isClosed) return;
    _avatar.add(
      AvatarStateUpdate(
        conversationId,
        emotion: emotion,
        intensity: intensity,
        conversationState: state,
      ),
    );
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

  ChatHandlers _handlers(String liveId) => ChatHandlers(
    onEvent: (_) => backend?.chatAnswered(),
    onCompanionState: (s) {
      _companion = s;
      _avatarState(emotion: s.emotion, intensity: s.intensity);
    },
    onDelta: (text) {
      final live = _live;
      if (live == null) _avatarState(state: AvatarConversationState.speaking);
      // Appended exactly as received (contract C2).
      _live = (live ?? _liveBubble(liveId)).withContent(
        (live?.content ?? '') + text,
      );
      _notify();
    },
    onUiAction: (action, urgent) {
      _noteUiAction(action);
      safety?.handleUiAction(action);
    },
    onHandoff: (handoff) {
      _textOnlyEvents++;
      _notify();
      safety?.handleHandoff(handoff);
    },
    onRisk: (risk) {
      if (risk.showsCrisisFlow) {
        _textOnlyEvents++;
        _notify();
      }
      safety?.handleRisk(risk);
    },
  );

  /// Exercise ui_actions (web useSpokenReplies.ts EXERCISE_ACTIONS), also
  /// the ones mobile does not run yet.
  static const Set<String> exerciseActions = {
    'start_breathing',
    'start_grounding',
    'start_plan',
    'stop_breathing',
    'pause_breathing',
  };
  static const Set<String> exerciseStartActions = {
    'start_breathing',
    'start_grounding',
    'start_plan',
  };

  void _noteUiAction(UiAction action) {
    if (!exerciseActions.contains(action.name)) return;
    _textOnlyEvents++;
    if (exerciseStartActions.contains(action.name)) _exerciseStarts++;
    _notify();
  }

  ChatMessage _liveBubble(String id) => ChatMessage(
    id: id,
    conversationId: conversationId,
    sender: 'ai',
    content: '',
    timestamp: _now(),
    emotion: Emotion.neutral,
  );

  /// The last [contextTurns] messages, minus saved fallback replies.
  List<ChatTurn> _context() {
    final history = [
      for (final m in _messages)
        if (!m.isFallback) m,
    ];
    final start = history.length > contextTurns
        ? history.length - contextTurns
        : 0;
    return [
      for (final m in history.sublist(start))
        ChatTurn(
          role: m.isUser ? historyRoleUser : historyRoleAssistant,
          content: m.content,
        ),
    ];
  }

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isTyping) return;

    // Context is taken BEFORE the new message is added.
    final context = _context();

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
      final liveId = _newId();
      final warmup = service.isConfigured ? backend : null;
      _isTyping = true;
      _notify();
      _avatarState(state: AvatarConversationState.thinking);
      warmup?.chatStarted();
      try {
        final result = await service.sendMessage(
          userId: uid,
          conversationId: conversationId,
          text: trimmed,
          context: context,
          handlers: _handlers(liveId),
          session: session,
          onResolutionSent: () => safety?.crisisResolutionSent(),
          // Only the first send waits for the chat warm-up (Ahmad,
          // 2026-10-18); the waking line shows meanwhile, typing stays on.
          beforeRequest: warmup?.holdFirstSend,
        );
        // A reply or any HTTP status: the service answered. Timeout or
        // network: it did not. Anything else (no token, bad redirect):
        // unknown.
        final code = result.failureCode;
        warmup?.chatFinished(
          reached: code == 'timeout' || code == 'network'
              ? false
              : code == null || int.tryParse(code) != null
              ? true
              : null,
        );
        _currentEmotion = result.emotion;
        _messages.add(
          ChatMessage(
            id: liveId,
            conversationId: conversationId,
            sender: 'ai',
            content: result.reply,
            timestamp: _live?.timestamp ?? _now(),
            emotion: result.emotion,
          ),
        );
      } finally {
        _live = null;
        _isTyping = false;
        _avatarState(state: AvatarConversationState.idle);
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

  /// One audio turn (Prompt 26, call screen only). Same context, session,
  /// avatar and safety handling as [send]; the user bubble appears when the
  /// `transcript` event arrives (not when [saveTranscript] is false: a
  /// Retry whose transcript is already in the chat). Before the upload,
  /// chat and crisis /health must both answer 200
  /// ([BackendWarmup.holdForAudio]).
  ///
  /// Nothing is queued offline and nothing is invented on failure: no
  /// fallback reply, and a transcript bubble that could not be saved is
  /// removed again. The caller shows the error and Retry.
  Future<AudioSendResult> sendVoice(
    AudioUpload audio, {
    bool saveTranscript = true,
  }) async {
    if (_isTyping) return const AudioSendResult(failureCode: 'busy');
    if (!await isOnline()) {
      return const AudioSendResult(failureCode: 'offline');
    }
    final context = _context();
    final liveId = _newId();
    final warmup = service.isConfigured ? backend : null;
    ChatMessage? shown;
    _isTyping = true;
    _notify();
    _avatarState(state: AvatarConversationState.thinking);
    warmup?.chatStarted();
    try {
      final base = _handlers(liveId);
      final result = await service.sendAudio(
        userId: uid,
        conversationId: conversationId,
        audio: audio,
        context: context,
        handlers: ChatHandlers(
          onEvent: base.onEvent,
          onCompanionState: base.onCompanionState,
          onDelta: base.onDelta,
          onUiAction: base.onUiAction,
          onHandoff: base.onHandoff,
          onRisk: base.onRisk,
          onTranscript: (text) {
            if (!saveTranscript) return;
            final bubble = shown = ChatMessage(
              id: _newId(),
              conversationId: conversationId,
              sender: 'user',
              content: text,
              timestamp: _now(),
              emotion: Emotion.neutral,
            );
            _messages.add(bubble);
            _notify();
          },
        ),
        session: session,
        onResolutionSent: () => safety?.crisisResolutionSent(),
        beforeRequest: warmup?.holdForAudio,
        saveTranscript: saveTranscript,
      );
      final code = result.failureCode;
      warmup?.chatFinished(
        reached: code == 'timeout' || code == 'network'
            ? false
            : code == null || int.tryParse(code) != null
            ? true
            : null,
      );
      if (shown != null && !result.transcriptSaved) _messages.remove(shown);
      final reply = result.reply;
      if (reply != null) {
        _currentEmotion = result.emotion ?? Emotion.neutral;
        _messages.add(
          ChatMessage(
            id: liveId,
            conversationId: conversationId,
            sender: 'ai',
            content: reply,
            timestamp: _live?.timestamp ?? _now(),
            emotion: _currentEmotion,
          ),
        );
      }
      return result;
    } finally {
      _live = null;
      _isTyping = false;
      _avatarState(state: AvatarConversationState.idle);
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    backend?.removeListener(_notify);
    _avatar.close();
    super.dispose();
  }
}
