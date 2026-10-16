import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'koi_chat_client.dart';

void main() {
  late HttpServer server;
  late KoiChatClient client;
  var chatCalls = 0;
  var crisisCalls = 0;
  var lastCrisisBody = '';

  setUp(() async {
    chatCalls = 0;
    crisisCalls = 0;
    lastCrisisBody = '';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path == '/api/v1/crisis') {
        crisisCalls++;
        lastCrisisBody = await utf8.decodeStream(request);
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'crisis_score': 0.8,
            'risk_category': 'HIGH',
            'modalities_used': ['text'],
            'trigger_flags': ['distress'],
          }));
        await request.response.close();
        return;
      }
      chatCalls++;
      if (request.uri.path.contains('/unauthorized')) {
        request.response.statusCode = 401;
        await request.response.close();
        return;
      }
      final handoff = chatCalls > 1
          ? 'event: handoff\ndata: {"to":"crisis","reason":"risk"}\n\n'
          : '';
      final frames = [
        'event: latency\ndata: {"latency_ms":12}\n\n',
        'event: companion_state\ndata: {"emotion":"joy","intensity":0.7}\n\n',
        'event: delta\ndata: {"text":"سلام 😀"}\n\n',
        handoff,
        'event: unknown\ndata: {"ignored":true}\n\n',
        'event: done\ndata: {"full_text":"سلام 😀","companion_state":{"emotion":"joy","intensity":0.7}}\n\n',
      ].join();
      request.response.headers.contentType = ContentType('text', 'event-stream');
      final bytes = utf8.encode(frames);
      for (var i = 0; i < bytes.length; i += 2) {
        request.response.add(bytes.sublist(i, i + 2 > bytes.length ? bytes.length : i + 2));
        await Future<void>.delayed(Duration.zero);
      }
      await request.response.close();
    });
    client = KoiChatClient(
      chatBaseUrl: 'http://127.0.0.1:${server.port}',
      crisisBaseUrl: 'http://127.0.0.1:${server.port}',
      getToken: () async => 'test-token',
    );
  });

  tearDown(() => server.close(force: true));

  test('streams split UTF-8 SSE and preserves contract callback order', () async {
    final state = KoiConversationState();
    final events = <String>[];
    final result = await client.sendMessage(
      text: 'hello',
      history: const [ChatTurn(ChatRole.user, 'old')],
      state: state,
      handlers: ChatHandlers(
        onCompanionState: (_) => events.add('state'),
        onDelta: (_) => events.add('delta'),
        onUiAction: (_, __) => events.add('action'),
      ),
    );
    expect(result.reply, 'سلام 😀');
    expect(result.companionState.emotion, Emotion.joy);
    expect(result.latencyMs, 12);
    expect(events, ['state', 'delta']);
  });

  test('opens crisis flow once for repeated handoffs and resolves held risk', () async {
    final state = KoiConversationState();
    var handoffs = 0;
    var crises = 0;
    final handlers = ChatHandlers(
      onHandoff: (_) => handoffs++,
      onCrisis: (_) => crises++,
    );
    final handoffClient = KoiChatClient(
      chatBaseUrl: 'http://127.0.0.1:${server.port}',
      crisisBaseUrl: '',
      getToken: () async => 'test-token',
    );
    await handoffClient.sendMessage(text: 'one', history: const [], state: state, handlers: handlers);
    await handoffClient.sendMessage(text: 'two', history: const [], state: state, handlers: handlers);
    expect(crisisCalls, 0);
    expect(crises, 0);
    expect(handoffs, 1);
    state.resolveCrisis('reached_out');
    expect(state.latestRisk, isNull);
  });

  test('401 returns the safe fallback reply', () async {
    final unauthorized = KoiChatClient(
      chatBaseUrl: 'http://127.0.0.1:${server.port}/unauthorized',
      crisisBaseUrl: '',
      getToken: () async => 'token',
    );
    final result = await unauthorized.sendMessage(
      text: 'hello',
      history: const [],
      state: KoiConversationState(),
    );
    expect(result.reply, contains("I'm having a little trouble"));
  });

  test('posts multipart crisis input and never throws on token failure', () async {
    final input = CrisisInput(
      text: 'typed',
      language: 'ur',
      turnId: 'abc',
      audio: http.MultipartFile.fromBytes('audio', [1, 2, 3], filename: 'a.wav'),
    );
    final result = await client.checkCrisis(input);
    expect(result, isNotNull);
    expect(lastCrisisBody, contains('name="audio"'));
    expect(lastCrisisBody, isNot(contains('name="text"')));

    final failing = KoiChatClient(
      chatBaseUrl: '',
      crisisBaseUrl: 'http://127.0.0.1:${server.port}',
      getToken: () async => throw StateError('token unavailable'),
    );
    expect(await failing.checkCrisis(const CrisisInput(turnId: 'x')), isNull);
  });
}
