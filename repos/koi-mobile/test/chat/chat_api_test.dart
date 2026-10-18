import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/avatar/avatar_state.dart';
import 'package:koi_mobile/chat/chat_api.dart';
import 'package:koi_mobile/safety/safety_contract.dart';

import '../support/fake_chat_server.dart';

const _token = 'fake-test-token-not-real';

Map<String, Object?> _body({
  String message = 'hello',
  List<ChatTurn> history = const [],
}) => chatRequestBody(message: message, sessionHistory: history);

void main() {
  late FakeChatServer server;
  setUp(() async => server = await FakeChatServer.start());
  tearDown(() => server.close());

  ChatApiClient client({Duration? deadline}) => ChatApiClient(
    baseUrl: server.base,
    deadline: deadline ?? const Duration(seconds: 240),
  );

  group('ATC-M2-01 configuration (web chatEndpoint())', () {
    test('valid bases; trailing / stripped', () {
      expect(
        parseApiBase('http://127.0.0.1:8000/')?.toString(),
        'http://127.0.0.1:8000',
      );
      expect(
        parseApiBase(' https://example.test/koi/ ')?.toString(),
        'https://example.test/koi',
      );
    });

    test('empty / invalid → not configured', () {
      for (final bad in [
        '',
        '   ',
        'ftp://example.test',
        'https://user:pw@example.test',
        'https://example.test/?a=1',
        'https://example.test/#x',
        'not a url',
      ]) {
        expect(parseApiBase(bad), isNull, reason: bad);
      }
      expect(ChatApiClient(baseUrl: '').isConfigured, isFalse);
    });

    test('not configured → ChatApiException, no request', () async {
      await expectLater(
        ChatApiClient(baseUrl: '').streamChat(idToken: _token, body: _body()),
        throwsA(
          isA<ChatApiException>().having(
            (e) => e.code,
            'code',
            ChatApiException.notConfigured,
          ),
        ),
      );
    });
  });

  group('ATC-M2-02 request', () {
    test('body keys, roles user/assistant, no risk; Bearer + Accept', () async {
      server.handler = (req, _) => writeSse(req, okTurn());
      final body = chatRequestBody(
        message: 'now',
        sessionHistory: const [
          ChatTurn(role: 'user', content: 'u'),
          ChatTurn(role: 'model', content: 'm'),
          ChatTurn(role: 'ai', content: 'a'),
          ChatTurn(role: 'assistant', content: 'x'),
        ],
        exerciseState: 'opaque.TOKEN==',
        clientEvent: ClientEvent.playbackDone,
        crisisPath: CrisisPath.reachedOut,
      );
      await client().streamChat(idToken: _token, body: body);

      final seen = server.requests.single;
      expect(seen.method, 'POST');
      expect(seen.uri.path, '/api/v1/chat');
      expect(seen.header('authorization'), 'Bearer $_token');
      expect(seen.header('accept'), 'text/event-stream');
      expect(seen.header('content-type'), startsWith('application/json'));
      final json = seen.json;
      expect(json.keys.toSet(), {
        'message',
        'session_history',
        'exercise_state',
        'client_event',
        'policy_event',
        'crisis_path',
      });
      expect(json.containsKey('risk'), isFalse);
      expect(json['message'], 'now');
      expect(
        (json['session_history']! as List).map((t) => (t as Map)['role']),
        ['user', 'assistant', 'assistant', 'assistant'],
      );
      expect(json['exercise_state'], 'opaque.TOKEN==');
      expect(json['client_event'], 'playback_done');
      expect(json['policy_event'], 'crisis_resolved');
      expect(json['crisis_path'], 'reached_out');
    });

    test('defaults: every key present, null where unknown', () {
      expect(_body(), {
        'message': 'hello',
        'session_history': <Object?>[],
        'exercise_state': null,
        'client_event': 'none',
        'policy_event': null,
        'crisis_path': null,
      });
    });
  });

  group('ATC-M2-03 stream', () {
    test(
      'parses SSE split across chunks; companion_state before text',
      () async {
        server.handler = (req, _) =>
            writeSse(req, okTurn(a: 'سلام 😀', b: ' ok'), chunkBytes: 1);
        final order = <String>[];
        final r = await client().streamChat(
          idToken: _token,
          body: _body(),
          handlers: ChatHandlers(
            onCompanionState: (_) => order.add('state'),
            onDelta: (_) => order.add('delta'),
          ),
        );
        expect(order, ['state', 'delta', 'delta']);
        expect(r.fullText, 'سلام 😀 ok');
        expect(r.companionState.emotion, AvatarEmotion.joy);
        expect(r.latencyMs, 12);
        expect((r.exerciseStateChanged, r.exerciseState), (true, 'tok-1'));
      },
    );

    test('401 / 500: status only, the body is never surfaced', () async {
      for (final status in [401, 500]) {
        server.handler = (req, _) async {
          req.response
            ..statusCode = status
            ..write('{"detail":"PRIVATE generation output"}');
          await req.response.close();
        };
        final c = client();
        Object? error;
        try {
          await c.streamChat(idToken: _token, body: _body());
        } catch (e) {
          error = e;
        }
        expect(error, isA<ChatApiException>());
        expect((error! as ChatApiException).code, '$status');
        expect('$error', isNot(contains('PRIVATE')));
        expect(c.lastDiagnostics!.status, '$status');
      }
    });

    test('network failure → ChatApiException(network)', () async {
      final c = ChatApiClient(baseUrl: server.base);
      await server.close();
      await expectLater(
        c.streamChat(idToken: _token, body: _body()),
        throwsA(
          isA<ChatApiException>().having((e) => e.code, 'code', 'network'),
        ),
      );
      expect(c.lastDiagnostics!.status, 'network');
    });
  });

  group('ATC-M2-04 C7: 303 redirect-and-poll', () {
    test('two 303 hops → GET poll URL with Authorization, then SSE', () async {
      server.handler = (req, seen) async {
        final n = server.requests.length;
        if (n <= 2) {
          req.response
            ..statusCode = 303
            ..headers.set('location', '/api/v1/chat?__poll=abc');
          await req.response.close();
          return;
        }
        await writeSse(req, okTurn());
      };
      final c = client();
      final r = await c.streamChat(idToken: _token, body: _body());
      expect(r.fullText, 'Hello there.');
      expect(server.requests.map((s) => s.method), ['POST', 'GET', 'GET']);
      for (final hop in server.requests.skip(1)) {
        expect(hop.uri.queryParameters['__poll'], 'abc');
        expect(hop.header('authorization'), 'Bearer $_token');
        expect(hop.header('accept'), 'text/event-stream');
      }
      expect(c.lastDiagnostics!.hops, 2);
      expect(c.lastDiagnostics!.status, '200');
    });

    test('cross-origin Location is rejected (token never sent)', () async {
      final other = await FakeChatServer.start();
      addTearDown(other.close);
      server.handler = (req, _) async {
        req.response
          ..statusCode = 303
          ..headers.set('location', '${other.base}/poll');
        await req.response.close();
      };
      await expectLater(
        client().streamChat(idToken: _token, body: _body()),
        throwsA(
          isA<ChatApiException>().having(
            (e) => e.code,
            'code',
            ChatApiException.redirect,
          ),
        ),
      );
      expect(other.requests, isEmpty);
    });

    test('more than 10 hops fails', () async {
      server.handler = (req, _) async {
        req.response
          ..statusCode = 303
          ..headers.set('location', '/api/v1/chat?__poll=same');
        await req.response.close();
      };
      await expectLater(
        client().streamChat(idToken: _token, body: _body()),
        throwsA(isA<ChatApiException>()),
      );
      expect(server.requests, hasLength(11)); // POST + 10 GETs
    });

    test('one overall deadline across hops; no callbacks after it', () async {
      server.handler = (req, _) async {
        if (req.method == 'POST') {
          req.response
            ..statusCode = 303
            ..headers.set('location', '/api/v1/chat?__poll=1');
          await req.response.close();
          return;
        }
        req.response.headers.contentType = ContentType('text', 'event-stream');
        req.response.write(sseFrame('delta', {'text': 'partial'}));
        await req.response.flush();
        await Future<void>.delayed(const Duration(seconds: 5));
        req.response.write(sseFrame('delta', {'text': 'late'}));
        await req.response.close();
      };
      final deltas = <String>[];
      final c = client(deadline: const Duration(milliseconds: 400));
      final watch = Stopwatch()..start();
      await expectLater(
        c.streamChat(
          idToken: _token,
          body: _body(),
          handlers: ChatHandlers(onDelta: deltas.add),
        ),
        throwsA(isA<ChatTimeoutException>()),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
      expect(c.lastDiagnostics!.status, 'timeout');
      expect(c.lastDiagnostics!.hops, 1);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(deltas, ['partial']);
    });

    test('the default deadline is 240 s, max 10 hops', () {
      final c = ChatApiClient(baseUrl: 'http://127.0.0.1:1');
      expect(c.deadline, const Duration(seconds: 240));
      expect(c.maxHops, 10);
    });
  });

  group('ATC-M2-05 diagnostics', () {
    test('one debug line: time, status, hops, elapsed, event names; '
        'never the token or text', () async {
      server.handler = (req, _) => writeSse(req, okTurn(a: 'SECRET words'));
      final logs = <String>[];
      final original = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
      try {
        await ChatApiClient(
          baseUrl: server.base,
          now: () => DateTime(2026, 10, 18, 9, 5, 7),
        ).streamChat(
          idToken: _token,
          body: _body(message: 'SECRET message'),
        );
      } finally {
        debugPrint = original;
      }
      expect(logs, hasLength(1));
      expect(
        logs.single,
        matches(
          RegExp(
            r'^\[KOI\] chat: 09:05:07 status=200 hops=0 elapsed=\d+\.\ds '
            r'backend_events=latency,companion_state,delta,state,done$',
          ),
        ),
      );
      final all = logs.join('\n');
      expect(all, isNot(contains(_token)));
      expect(all, isNot(contains('SECRET')));
      expect(all, isNot(contains('127.0.0.1')));
    });
  });

  group('ATC-M2-06 GET /health', () {
    test('no Authorization; true on 2xx, false otherwise', () async {
      var status = 200;
      server.handler = (req, _) async {
        req.response
          ..statusCode = status
          ..write('{"status":"ok"}');
        await req.response.close();
      };
      expect(await client().checkHealth(), isTrue);
      final seen = server.requests.single;
      expect((seen.method, seen.uri.path), ('GET', '/health'));
      expect(seen.header('authorization'), isNull);

      status = 503;
      expect(await client().checkHealth(), isFalse);
      status = 204; // only 200 counts (Ahmad, 2026-10-18)
      expect(await client().checkHealth(), isFalse);
      expect(await ChatApiClient(baseUrl: '').checkHealth(), isFalse);
    });

    test('follows 303 hops (as chat does), still without a token', () async {
      server.handler = (req, _) async {
        if (server.requests.length <= 2) {
          req.response
            ..statusCode = 303
            ..headers.set('location', '/health?__poll=1');
        } else {
          req.response.write('ok');
        }
        await req.response.close();
      };
      expect(await client().checkHealth(), isTrue);
      expect(server.requests, hasLength(3));
      for (final r in server.requests) {
        expect(r.method, 'GET');
        expect(r.uri.path, '/health');
        expect(r.header('authorization'), isNull);
      }
    });

    test('the timeout limits one try', () async {
      final never = Completer<void>();
      server.handler = (req, _) async {
        await never.future;
      };
      final watch = Stopwatch()..start();
      expect(
        await client().checkHealth(const Duration(milliseconds: 200)),
        isFalse,
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      never.complete();
    });
  });
}
