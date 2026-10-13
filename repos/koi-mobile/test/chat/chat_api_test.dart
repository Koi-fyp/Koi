import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/chat/chat_api.dart';
import 'package:koi_mobile/core/emotion.dart';

/// A fake local server: returns [status] and streams [chunks] (each chunk
/// arrives separately, so frames can be split anywhere).
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.status, this.chunks);
  final int status;
  final List<String> chunks;
  RequestOptions? lastRequest;
  Object? lastBody;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    lastBody = options.data;
    final stream = Stream<Uint8List>.fromIterable(
      chunks.map((c) => Uint8List.fromList(utf8.encode(c))),
    );
    return ResponseBody(
      stream,
      status,
      headers: {
        Headers.contentTypeHeader: ['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ChatApiClient _client(_FakeAdapter adapter) => ChatApiClient(
  baseUrl: 'http://fake.local',
  dio: Dio()..httpClientAdapter = adapter,
);

void main() {
  group('SseChatParser', () {
    test('latency, deltas and done (full_text overrides, emotion)', () {
      final deltas = <String>[];
      final p = SseChatParser(onDelta: deltas.add)
        ..add('event: latency\ndata: {"latency_ms": 412}\n\n')
        ..add('event: delta\ndata: {"text": "Hel"}\n\n')
        ..add('event: delta\ndata: {"text": "lo"}\n\n')
        ..add(
          'event: done\ndata: {"full_text": "Hello!", '
          '"companion_state": {"emotion": "happy"}}\n\n',
        );
      expect(deltas, ['Hel', 'lo']);
      expect(p.result.fullText, 'Hello!');
      expect(p.result.emotion, Emotion.happy);
      expect(p.result.latencyMs, 412);
    });

    test('frames split across chunks; trailing partial frame waits', () {
      final p = SseChatParser();
      p.add('event: del');
      p.add('ta\ndata: {"te');
      expect(p.fullText, ''); // nothing complete yet
      p.add('xt": "A"}\n');
      expect(p.fullText, ''); // still no blank line
      p.add(
        '\nevent: delta\ndata: {"text": "B"}\n\nevent: delta\ndata: {"text": "C"}',
      );
      expect(p.fullText, 'AB'); // "C" is an unterminated frame
      p.add('\n\n');
      expect(p.fullText, 'ABC');
    });

    test('bad JSON lines are skipped, the stream continues', () {
      final p = SseChatParser()
        ..add('event: delta\ndata: {not json\n\n')
        ..add('event: delta\ndata: {"text": "ok"}\n\n');
      expect(p.fullText, 'ok');
    });

    test('empty full_text keeps the deltas; unknown emotion → neutral', () {
      final p = SseChatParser()
        ..add('event: delta\ndata: {"text": "x"}\n\n')
        ..add(
          'event: done\ndata: {"full_text": "", '
          '"companion_state": {"emotion": "joy"}}\n\n',
        );
      expect(p.fullText, 'x');
      expect(p.emotion, Emotion.neutral);
    });

    test('non-number latency_ms → null; event persists across frames', () {
      final p = SseChatParser()
        ..add('event: latency\ndata: {"latency_ms": "fast"}\n\n')
        ..add('event: delta\ndata: {"text": "a"}\n\n')
        ..add('data: {"text": "b"}\n\n'); // still "delta"
      expect(p.latencyMs, isNull);
      expect(p.fullText, 'ab');
    });
  });

  group('ChatApiClient.streamChat (fake local stream)', () {
    test('POSTs JSON with the Bearer token and parses the stream', () async {
      final adapter = _FakeAdapter(200, [
        'event: latency\ndata: {"latency_ms": 90}\n\nevent: del',
        'ta\ndata: {"text": "Hi "}\n\nevent: delta\ndata: {"text": "there"}\n\n',
        'event: done\ndata: {"full_text": "Hi there", "companion_state": {"emotion": "calm"}}\n\n',
      ]);
      final r = await _client(adapter).streamChat(
        idToken: 'tok',
        message: 'hello',
        sessionHistory: const [ChatTurn(role: 'user', content: 'earlier')],
      );
      expect(r.fullText, 'Hi there');
      expect(r.emotion, Emotion.calm);
      expect(r.latencyMs, 90);

      final req = adapter.lastRequest!;
      expect(req.method, 'POST');
      expect(req.uri.toString(), 'http://fake.local/api/v1/chat');
      expect(req.headers['Authorization'], 'Bearer tok');
      expect(jsonDecode(adapter.lastBody! as String), {
        'message': 'hello',
        'session_history': [
          {'role': 'user', 'content': 'earlier'},
        ],
      });
    });

    test('non-200: throws with status and body, never parses SSE', () async {
      final adapter = _FakeAdapter(401, [
        '{"detail": "invalid token"}',
        // Would be parsed if the status were ignored:
        '\n\nevent: delta\ndata: {"text": "SHOULD NOT APPEAR"}\n\n',
      ]);
      await expectLater(
        _client(adapter)
            .streamChat(idToken: 't', message: 'm', sessionHistory: const []),
        throwsA(
          isA<ChatApiException>().having(
            (e) => e.message,
            'message',
            allOf(
              startsWith(
                '/api/v1/chat returned 401: {"detail": "invalid token"}',
              ),
            ),
          ),
        ),
      );
    });

    test('error body is cut to 300 characters', () async {
      final adapter = _FakeAdapter(500, ['x' * 1000]);
      try {
        await _client(adapter)
            .streamChat(idToken: 't', message: 'm', sessionHistory: const []);
        fail('should throw');
      } on ChatApiException catch (e) {
        expect(e.message, '/api/v1/chat returned 500: ${'x' * 300}');
      }
    });

    test('no base URL configured: throws before any request', () async {
      final adapter = _FakeAdapter(200, const []);
      final client = ChatApiClient(
        baseUrl: '',
        dio: Dio()..httpClientAdapter = adapter,
      );
      expect(client.isConfigured, isFalse);
      await expectLater(
        client.streamChat(idToken: 't', message: 'm', sessionHistory: const []),
        throwsA(isA<ChatApiException>()),
      );
      expect(adapter.lastRequest, isNull);
    });

    test('no --dart-define is invented: the default base is empty', () {
      expect(koiApiBase, isEmpty);
    });

    test('Q3 role constants are isolated', () {
      expect(historyRoleUser, 'user');
      expect(historyRoleAi, 'model'); // web value; TODO(Q3)
    });
  });
}
