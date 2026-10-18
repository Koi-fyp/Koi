import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../avatar/avatar_state.dart' show AvatarEmotion;
import '../core/emotion.dart';
import '../safety/safety_contract.dart';

// Contract: repos/koi-ai-engine/docs/contracts/KOI_CLIENT_CONTRACT_v1.md on
// origin/feat/exercise-director-modal (§1-2, v1.1 ADDITIONS, v1.1 C), and its
// Dart reference client clients/dart/koi_chat_client.dart. Web transport:
// origin/feat/web-v11-wiring src/lib/conversation/jsonChatTransport.ts.

/// Base URL of the chat service, from `--dart-define=KOI_API_BASE=...`
/// (web: NEXT_PUBLIC_KOI_API_BASE). There is deliberately NO default and the
/// URL is not written anywhere in the repo; until it is set, sending falls
/// back to the offline reply.
const String koiApiBase = String.fromEnvironment('KOI_API_BASE');

/// Base URL of the crisis (TSD) service, from `--dart-define=KOI_CRISIS_BASE`.
/// Only its `GET /health` is ever called, to warm it. C8 decided (Ahmad,
/// 2026-10-18): clients never call POST /api/v1/crisis; the chat server
/// scores risk every turn and sends the `risk` event. Empty = not warmed.
const String koiCrisisBase = String.fromEnvironment('KOI_CRISIS_BASE');

/// web chatEndpoint(): http/https only, no user/password/query/fragment, a
/// trailing `/` stripped. null when empty or invalid.
Uri? parseApiBase(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri == null ||
      !(uri.scheme == 'http' || uri.scheme == 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  final path = uri.path.endsWith('/')
      ? uri.path.substring(0, uri.path.length - 1)
      : uri.path;
  return uri.replace(path: path);
}

/// History role names sent in `session_history` (contract §1:
/// `"user" | "assistant"`).
const String historyRoleUser = 'user';
const String historyRoleAssistant = 'assistant';

/// One `session_history` turn.
@immutable
class ChatTurn {
  const ChatTurn({required this.role, required this.content});
  final String role;
  final String content;

  /// Older names for the AI side (`model`, our stored sender `ai`) are sent
  /// as `assistant`, like web normalizeHistory().
  Map<String, String> toJson() => {
    'role': role == historyRoleUser ? historyRoleUser : historyRoleAssistant,
    'content': content,
  };
}

/// The `companion_state` event: `{emotion, intensity}`. Unknown emotion →
/// neutral, intensity clamped to 0..1, missing → `{neutral, 0.4}` (v1.1, the
/// reference client's CompanionState.fromJson).
@immutable
class CompanionState {
  const CompanionState(this.emotion, this.intensity);
  final AvatarEmotion emotion;
  final double intensity;

  static const CompanionState fallback = CompanionState(
    AvatarEmotion.neutral,
    0.4,
  );

  static CompanionState fromJson(Object? raw) {
    final map = raw is Map ? raw : const <Object?, Object?>{};
    final emotion = AvatarEmotion.values.firstWhere(
      (e) => e.name == map['emotion'],
      orElse: () => AvatarEmotion.neutral,
    );
    final intensity = map['intensity'];
    return CompanionState(
      emotion,
      intensity is num && intensity.isFinite
          ? intensity.toDouble().clamp(0.0, 1.0)
          : 0.4,
    );
  }
}

/// Callbacks for the events of one chat response (reference client
/// `ChatHandlers`). All are optional.
class ChatHandlers {
  const ChatHandlers({
    this.onEvent,
    this.onCompanionState,
    this.onDelta,
    this.onUiAction,
    this.onHandoff,
    this.onRisk,
  });

  /// Any SSE frame arrived (its event name); used for "waking up".
  final void Function(String event)? onEvent;
  final void Function(CompanionState state)? onCompanionState;
  final void Function(String text)? onDelta;

  /// [urgent]: no reply text had arrived yet (§2 event 2).
  final void Function(UiAction action, bool urgent)? onUiAction;

  /// Only `to == "crisis"`. Repeats every turn until crisis_resolved.
  final void Function(Handoff handoff)? onHandoff;

  /// `status: "unavailable"` means no score this turn, never "safe".
  final void Function(RiskResult risk)? onRisk;
}

/// streamChat()'s result.
@immutable
class ChatStreamResult {
  const ChatStreamResult({
    required this.fullText,
    required this.companionState,
    required this.latencyMs,
    required this.exerciseStateChanged,
    required this.exerciseState,
  });

  /// The untrimmed reply.
  final String fullText;
  final CompanionState companionState;
  final int? latencyMs;

  /// True when `state` or `done` carried `exercise_state` as a string or an
  /// explicit null; then [exerciseState] is the new value.
  final bool exerciseStateChanged;
  final String? exerciseState;

  /// The label stored with the AI message (web storedEmotion()).
  Emotion get emotion => storedEmotion(companionState.emotion.name);
}

/// A failed chat request. [code] is an HTTP status or a short error code;
/// never a response body.
class ChatApiException implements Exception {
  const ChatApiException(this.code);
  final String code;

  static const String notConfigured = 'not_configured';
  static const String redirect = 'redirect';
  static const String noBody = 'no_body';
  static const String emptyReply = 'empty_reply';

  @override
  String toString() => 'ChatApiException($code)';
}

/// The overall deadline passed (contract C7: at least 240 s).
class ChatTimeoutException implements Exception {
  const ChatTimeoutException();
  @override
  String toString() => 'ChatTimeoutException';
}

/// Incremental SSE parser, after the reference client's _handleFrame with
/// these rules:
/// - frames end at a blank line (`\n\n` or `\r\n\r\n`); the trailing
///   partial frame waits for more text, and [close] flushes it;
/// - `event:` / `data:` with or without a space; several `data:` lines are
///   joined with `\n`; the event name is `message` again for every frame;
/// - `delta.text` is appended exactly as received (C2: never trimmed);
///   a non-empty `done.full_text` replaces it;
/// - unknown events and malformed JSON are ignored silently.
class SseChatParser {
  SseChatParser({this.handlers = const ChatHandlers()});

  final ChatHandlers handlers;

  static final RegExp _frameEnd = RegExp(r'\r?\n\r?\n');
  static final RegExp _lineEnd = RegExp(r'\r?\n');

  String _buffer = '';
  bool _closed = false;
  bool _sawText = false;
  bool _sawRisk = false;

  String fullText = '';
  CompanionState companionState = CompanionState.fallback;
  int? latencyMs;
  bool exerciseStateChanged = false;
  String? exerciseState;

  /// Event names in arrival order, each once (diagnostics only).
  final List<String> eventNames = [];

  void add(String text) {
    if (_closed) return;
    _buffer += text;
    final frames = _buffer.split(_frameEnd);
    _buffer = frames.removeLast();
    for (final frame in frames) {
      _frame(frame);
    }
  }

  /// End of stream: handles a last frame that had no blank line after it.
  void close() {
    if (_closed) return;
    if (_buffer.trim().isNotEmpty) _frame(_buffer);
    _buffer = '';
    _closed = true;
  }

  /// Stops all further callbacks (deadline passed).
  void abandon() => _closed = true;

  void _frame(String frame) {
    var event = 'message';
    final data = <String>[];
    for (final line in frame.split(_lineEnd)) {
      if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        final value = line.substring(5);
        data.add(value.startsWith(' ') ? value.substring(1) : value);
      }
    }
    if (data.isEmpty) return;
    Object? decoded;
    try {
      decoded = jsonDecode(data.join('\n'));
    } catch (_) {
      return;
    }
    if (decoded is! Map) return;
    if (!eventNames.contains(event)) eventNames.add(event);
    handlers.onEvent?.call(event);
    _handle(event, decoded);
  }

  void _handle(String event, Map<dynamic, dynamic> map) {
    switch (event) {
      case 'latency':
        final v = map['latency_ms'];
        if (v is num && v.isFinite) latencyMs = v.toInt();
      case 'companion_state':
        companionState = CompanionState.fromJson(map);
        handlers.onCompanionState?.call(companionState);
      case 'delta':
        final text = map['text'];
        if (text is String && text.isNotEmpty) {
          fullText += text;
          _sawText = true;
          handlers.onDelta?.call(text);
        }
      case 'ui_action':
        final action = UiAction.fromJson(map);
        if (action != null) handlers.onUiAction?.call(action, !_sawText);
      case 'handoff':
        final handoff = Handoff.fromJson(map);
        if (handoff != null && handoff.isCrisis) {
          handlers.onHandoff?.call(handoff);
        }
      case 'risk':
        _sawRisk = true;
        handlers.onRisk?.call(RiskResult.fromJson(_stringKeys(map)));
      case 'state':
        _exerciseState(map);
      case 'done':
        final full = map['full_text'];
        if (full is String && full.isNotEmpty) fullText = full;
        final state = map['companion_state'];
        if (state is Map) companionState = CompanionState.fromJson(state);
        _exerciseState(map);
        // Same object as the streamed `risk`; only used if that never came.
        final risk = map['risk'];
        if (!_sawRisk && risk is Map) {
          _sawRisk = true;
          handlers.onRisk?.call(RiskResult.fromJson(_stringKeys(risk)));
        }
      // `transcript` (audio turns only), `done.reply_backend`,
      // `reply_fallback_reason`, `trace` (C11, C4) and unknown events are
      // ignored.
    }
  }

  /// Contract §1: "Send back exactly what the last `state` event gave you".
  /// So a string replaces the token, an explicit null clears it (the
  /// exercise ended), a missing key changes nothing and any other value is
  /// ignored. The same rule applies to `done.exercise_state`.
  void _exerciseState(Map<dynamic, dynamic> map) {
    if (!map.containsKey('exercise_state')) return;
    final v = map['exercise_state'];
    if (v == null || v is String) {
      exerciseStateChanged = true;
      exerciseState = v as String?;
    }
  }

  static Map<String, Object?> _stringKeys(Map<dynamic, dynamic> map) => {
    for (final e in map.entries)
      if (e.key is String) e.key as String: e.value,
  };

  ChatStreamResult get result => ChatStreamResult(
    fullText: fullText,
    companionState: companionState,
    latencyMs: latencyMs,
    exerciseStateChanged: exerciseStateChanged,
    exerciseState: exerciseState,
  );
}

/// One line per chat request for failure reports. Holds no message text,
/// token or URL.
@immutable
class ChatDiagnostics {
  const ChatDiagnostics({
    required this.time,
    required this.status,
    required this.hops,
    required this.elapsed,
    required this.events,
  });

  final DateTime time;

  /// HTTP status, `timeout`, `network` or a [ChatApiException] code.
  final String status;
  final int hops;
  final Duration elapsed;
  final List<String> events;

  String get line {
    String two(int v) => v.toString().padLeft(2, '0');
    final t = '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
    final s = (elapsed.inMilliseconds / 1000).toStringAsFixed(1);
    return '[KOI] chat: $t status=$status hops=$hops elapsed=${s}s '
        'backend_events=${events.join(',')}';
  }
}

/// The JSON body of `POST /api/v1/chat` (contract §1). Every key is sent;
/// `risk` is not (C5: the server ignores it).
Map<String, Object?> chatRequestBody({
  required String message,
  required List<ChatTurn> sessionHistory,
  String? exerciseState,
  ClientEvent clientEvent = ClientEvent.none,
  CrisisPath? crisisPath,
}) => {
  'message': message,
  'session_history': [for (final t in sessionHistory) t.toJson()],
  'exercise_state': exerciseState,
  'client_event': clientEvent.wire,
  'policy_event': crisisPath == null ? null : crisisResolvedPolicyEvent,
  'crisis_path': crisisPath?.wire,
};

/// Calls the chat service: `POST {base}/api/v1/chat` (SSE) and
/// `GET {base}/health`.
///
/// Redirects are followed by hand (C7: Modal answers a request slower than
/// 150 s with a 303 to a poll URL, possibly several times). dart:io would
/// follow a 303 itself, but it reports "Redirect loop detected" when the
/// same Location comes back, stops after 5, and drops Authorization on a
/// cross-origin hop. Here: same origin only (scheme + host + port), https
/// (or loopback, for tests), at most [maxHops], all within one [deadline].
class ChatApiClient {
  ChatApiClient({
    required String baseUrl,
    Dio? dio,
    this.deadline = const Duration(seconds: 240),
    this.maxHops = 10,
    DateTime Function()? now,
  }) : base = parseApiBase(baseUrl),
       _dio = dio ?? Dio(),
       _now = now ?? DateTime.now;

  /// null when KOI_API_BASE is empty or invalid.
  final Uri? base;
  final Duration deadline;
  final int maxHops;
  final Dio _dio;
  final DateTime Function() _now;

  bool get isConfigured => base != null;

  /// The latest request's diagnostics (DEBUG menu "Copy last chat
  /// diagnostics").
  ChatDiagnostics? lastDiagnostics;

  Uri _url(String path) => base!.replace(path: '${base!.path}$path');

  Future<ChatStreamResult> streamChat({
    required String idToken,
    required Map<String, Object?> body,
    ChatHandlers handlers = const ChatHandlers(),
  }) {
    if (!isConfigured) {
      return Future.error(
        const ChatApiException(ChatApiException.notConfigured),
      );
    }
    final started = _now();
    final watch = Stopwatch()..start();
    final cancel = CancelToken();
    final parser = SseChatParser(handlers: handlers);
    final hops = _Hops();
    final done = Completer<ChatStreamResult>();
    var status = 'network';

    void finish() {
      final d = ChatDiagnostics(
        time: started,
        status: status,
        hops: hops.count,
        elapsed: watch.elapsed,
        events: List.unmodifiable(parser.eventNames),
      );
      lastDiagnostics = d;
      if (kDebugMode) debugPrint(d.line);
    }

    final timer = Timer(deadline, () {
      if (done.isCompleted) return;
      status = 'timeout';
      parser.abandon();
      cancel.cancel();
      finish();
      done.completeError(const ChatTimeoutException());
    });

    () async {
      final headers = {
        'Accept': 'text/event-stream',
        'Authorization': 'Bearer $idToken',
      };
      final res = await _request(
        'POST',
        _url('/api/v1/chat'),
        headers: {...headers, 'Content-Type': 'application/json'},
        followHeaders: headers,
        data: jsonEncode(body),
        cancel: cancel,
        hops: hops,
      );
      status = '${res.statusCode}';
      final stream = res.data;
      if (stream == null) {
        throw const ChatApiException(ChatApiException.noBody);
      }
      await for (final chunk in utf8.decoder.bind(stream.stream)) {
        parser.add(chunk);
      }
      parser.close();
      return parser.result;
    }().then(
      (result) {
        timer.cancel();
        if (done.isCompleted) return;
        finish();
        done.complete(result);
      },
      onError: (Object e) {
        timer.cancel();
        if (done.isCompleted) return;
        // Anything that is not ours (DioException, socket, decoding) is
        // reported as `network`, without its message.
        final error = e is ChatApiException
            ? e
            : const ChatApiException('network');
        status = error.code;
        finish();
        done.completeError(error);
      },
    );
    return done.future;
  }

  /// `GET {base}/health` with no token (C6), following Modal's 303 hops like
  /// chat does. true only on HTTP 200; [timeout] (default [deadline]) limits
  /// the whole try. One try: BackendWarmup retries.
  Future<bool> checkHealth([Duration? timeout]) async {
    if (!isConfigured) return false;
    final cancel = CancelToken();
    final timer = Timer(timeout ?? deadline, cancel.cancel);
    try {
      final res = await _request(
        'GET',
        _url('/health'),
        headers: const {},
        followHeaders: const {},
        cancel: cancel,
        hops: _Hops(),
      );
      _discard(res);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      timer.cancel();
    }
  }

  /// One request plus its redirect hops. Throws [ChatApiException] for a
  /// rejected redirect or a final non-2xx (status only, the body is
  /// discarded unread).
  Future<Response<ResponseBody>> _request(
    String method,
    Uri url, {
    required Map<String, String> headers,
    required Map<String, String> followHeaders,
    required CancelToken cancel,
    required _Hops hops,
    Object? data,
  }) async {
    var current = url;
    var res = await _dio.requestUri<ResponseBody>(
      current,
      data: data,
      cancelToken: cancel,
      options: _options(method, headers),
    );
    while (_isRedirect(res.statusCode)) {
      _discard(res);
      final location = res.headers.value('location');
      if (location == null || hops.count >= maxHops) {
        throw const ChatApiException(ChatApiException.redirect);
      }
      final next = current.resolve(location);
      if (!_allowedHop(next, url)) {
        throw const ChatApiException(ChatApiException.redirect);
      }
      hops.count++;
      current = next;
      // Every hop is a GET of the poll URL (Modal sends 303, which turns a
      // POST into a GET), with the same Authorization and Accept.
      res = await _dio.requestUri<ResponseBody>(
        current,
        cancelToken: cancel,
        options: _options('GET', followHeaders),
      );
    }
    final status = res.statusCode ?? 0;
    if (status < 200 || status > 299) {
      _discard(res);
      throw ChatApiException('$status');
    }
    return res;
  }

  Options _options(String method, Map<String, String> headers) => Options(
    method: method,
    headers: headers,
    responseType: ResponseType.stream,
    followRedirects: false,
    // Status is checked here, before anything is read.
    validateStatus: (_) => true,
    // Only the overall deadline limits a request; nothing cuts a slow
    // stream earlier.
    sendTimeout: deadline,
    receiveTimeout: deadline,
  );

  static bool _isRedirect(int? s) =>
      s == 301 || s == 302 || s == 303 || s == 307 || s == 308;

  static bool _allowedHop(Uri next, Uri original) {
    final sameOrigin =
        next.scheme == original.scheme &&
        next.host == original.host &&
        next.port == original.port;
    final secure = next.scheme == 'https' || next.host == '127.0.0.1';
    return sameOrigin && secure;
  }

  static void _discard(Response<ResponseBody> res) {
    try {
      res.data?.stream.listen(null, onError: (_) {}).cancel();
    } catch (_) {}
  }
}

class _Hops {
  int count = 0;
}
