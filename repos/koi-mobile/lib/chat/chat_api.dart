import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/emotion.dart';

/// Base URL of the chat endpoint, from `--dart-define=KOI_API_BASE=...`
/// (web: NEXT_PUBLIC_KOI_API_BASE). There is deliberately NO default: until
/// it is set (Q2), sending falls back to the web's offline reply.
const String koiApiBase = String.fromEnvironment('KOI_API_BASE');

/// History role names sent in `session_history`.
///
/// TODO(Q3): web sends 'model' for AI turns (useChat.ts), but
/// koi-ai-engine/app/models/schemas.py only accepts 'user' | 'assistant'.
/// Change [historyRoleAi] here once the real endpoint's accepted value is
/// confirmed.
const String historyRoleUser = 'user';
const String historyRoleAi = 'model';

/// conversationService.ts `ChatTurn`.
@immutable
class ChatTurn {
  const ChatTurn({required this.role, required this.content});
  final String role;
  final String content;

  Map<String, String> toJson() => {'role': role, 'content': content};
}

/// streamChat()'s result.
@immutable
class ChatStreamResult {
  const ChatStreamResult({
    required this.fullText,
    required this.emotion,
    required this.latencyMs,
  });
  final String fullText;
  final Emotion emotion;
  final num? latencyMs;
}

/// Non-200 from the endpoint (web: `/api/v1/chat returned <status>: <body>`).
class ChatApiException implements Exception {
  const ChatApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Incremental SSE parser with exactly streamChat()'s rules:
/// - frames are separated by a blank line ("\n\n"); the trailing partial
///   frame stays buffered until more text arrives;
/// - `event: X` sets the current event (it persists across frames, as in
///   web where `currentEvent` lives outside the loop);
/// - `data: {json}` lines are parsed; unparseable ones are skipped with a
///   warning;
/// - latency → latency_ms (number or null); delta → append `text`;
///   done → non-empty `full_text` replaces the text, and
///   companion_state.emotion goes through [normalizeEmotion].
class SseChatParser {
  SseChatParser({this.onDelta});

  final void Function(String chunk)? onDelta;

  String _buffer = '';
  String? _currentEvent;
  String fullText = '';
  Emotion emotion = Emotion.neutral;
  num? latencyMs;

  void add(String text) {
    _buffer += text;
    final frames = _buffer.split('\n\n');
    _buffer = frames.removeLast();
    for (final frame in frames) {
      for (final line in frame.split('\n')) {
        if (line.startsWith('event: ')) {
          _currentEvent = line.substring(7).trim();
        } else if (line.startsWith('data: ')) {
          Object? decoded;
          try {
            decoded = jsonDecode(line.substring(6));
          } catch (_) {
            debugPrint('[KOI] Unparseable SSE data line, skipping');
            continue;
          }
          if (decoded is! Map) {
            // JSON.parse would succeed but property reads give undefined.
            decoded = const <String, Object?>{};
          }
          _handle(decoded);
        }
      }
    }
  }

  void _handle(Map<dynamic, dynamic> payload) {
    switch (_currentEvent) {
      case 'latency':
        final v = payload['latency_ms'];
        latencyMs = v is num ? v : null;
      case 'delta':
        final v = payload['text'];
        final chunk = v is String ? v : '';
        if (chunk.isNotEmpty) {
          fullText += chunk;
          onDelta?.call(chunk);
        }
      case 'done':
        final full = payload['full_text'];
        if (full is String && full.isNotEmpty) fullText = full;
        final state = payload['companion_state'];
        if (state is Map) emotion = normalizeEmotion(state['emotion']);
    }
  }

  ChatStreamResult get result => ChatStreamResult(
    fullText: fullText,
    emotion: emotion,
    latencyMs: latencyMs,
  );
}

/// Mirrors streamChat() in
/// repos/koi-backend/nextjs_app/src/lib/conversation/conversationService.ts.
class ChatApiClient {
  ChatApiClient({required this.baseUrl, Dio? dio}) : _dio = dio ?? Dio();

  final String baseUrl;
  final Dio _dio;

  bool get isConfigured => baseUrl.isNotEmpty;

  Future<ChatStreamResult> streamChat({
    required String idToken,
    required String message,
    required List<ChatTurn> sessionHistory,
    void Function(String chunk)? onDelta,
  }) async {
    if (!isConfigured) {
      throw const ChatApiException(
        'KOI_API_BASE is not configured (Q2): no chat endpoint',
      );
    }
    final res = await _dio.post<ResponseBody>(
      '$baseUrl/api/v1/chat',
      data: jsonEncode({
        'message': message,
        'session_history': [for (final t in sessionHistory) t.toJson()],
      }),
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        responseType: ResponseType.stream,
        // Check status ourselves BEFORE parsing (web: `if (!res.ok)`).
        validateStatus: (_) => true,
      ),
    );

    final status = res.statusCode ?? 0;
    final body = res.data;
    if (status < 200 || status > 299) {
      var text = '';
      try {
        if (body != null) {
          text = await utf8.decoder.bind(body.stream).join();
        }
      } catch (_) {}
      throw ChatApiException(
        '/api/v1/chat returned $status: '
        '${text.length > 300 ? text.substring(0, 300) : text}',
      );
    }
    if (body == null) {
      throw const ChatApiException('/api/v1/chat returned no response body');
    }

    final parser = SseChatParser(onDelta: onDelta);
    await for (final chunk in utf8.decoder.bind(body.stream)) {
      parser.add(chunk);
    }
    return parser.result;
  }
}
