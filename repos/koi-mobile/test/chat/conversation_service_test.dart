import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_flutter_lib/services/crypto_service.dart';
import 'package:koi_mobile/chat/chat_api.dart';
import 'package:koi_mobile/chat/chat_session_state.dart';
import 'package:koi_mobile/chat/conversation_service.dart';
import 'package:koi_mobile/chat/crisis_api.dart';
import 'package:koi_mobile/chat/message_record.dart';
import 'package:koi_mobile/core/emotion.dart';
import 'package:koi_mobile/core/koi_cryptography.dart';
import 'package:koi_mobile/safety/safety_contract.dart';

import '../support/chat_fakes.dart';
import '../support/fake_chat_server.dart';

/// Logs the order of store writes vs API calls.
class _OrderStore extends MemoryMessageStore {
  _OrderStore(this.log);
  final List<String> log;
  @override
  Future<void> put(MessageRecord record) {
    log.add('store:${record.sender}');
    return super.put(record);
  }
}

class _OrderAdapter implements HttpClientAdapter {
  _OrderAdapter(this.log, this.status, this.body);
  final List<String> log;
  final int status;
  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) async {
    log.add('api');
    return ResponseBody(
      Stream.value(Uint8List.fromList(utf8.encode(body))),
      status,
    );
  }

  @override
  void close({bool force = false}) {}
}

ChatApiClient _api(List<String> log, {int status = 200, String body = ''}) =>
    ChatApiClient(
      baseUrl: 'http://fake.local',
      dio: Dio()..httpClientAdapter = _OrderAdapter(log, status, body),
    );

const _sse =
    'event: delta\ndata: {"text": "I hear you."}\n\n'
    'event: done\ndata: {"full_text": "I hear you.", '
    '"companion_state": {"emotion": "sorrow", "intensity": 0.5}}\n\n';

ConversationService _service({
  required MessageStore store,
  required RecordingSyncQueue queue,
  required ChatApiClient api,
  MessageCipher? cipher,
  String? token = 'tok',
}) {
  var n = 0;
  return ConversationService(
    cryptoContext: (_) async => testCryptoContext,
    cipher: cipher ?? FakeCipher(),
    store: store,
    syncQueue: queue,
    api: api,
    idToken: () async => token ?? (throw StateError('no user')),
    newId: () => 'id${n++}',
  );
}

void main() {
  test(
    'user message is saved BEFORE the API call; reply saved after',
    () async {
      final log = <String>[];
      final s = _service(
        store: _OrderStore(log),
        queue: RecordingSyncQueue(),
        api: _api(log, body: _sse),
      );
      final r = await s.sendMessage(
        userId: 'u1',
        conversationId: 'u1',
        text: 'I feel low',
        context: const [],
      );
      expect(log, ['store:user', 'api', 'store:ai']);
      expect(r.reply, 'I hear you.');
      expect(r.emotion, Emotion.sad); // sorrow → sad (web storedEmotion)
      expect(r.isFallback, isFalse);
    },
  );

  test('Q5: Firestore path uses conversationId = uid; priority 3', () async {
    final queue = RecordingSyncQueue();
    await _service(
      store: MemoryMessageStore(),
      queue: queue,
      api: _api([], body: _sse),
    ).sendMessage(
      userId: 'u1',
      conversationId: 'u1',
      text: 'hi',
      context: const [],
    );
    expect(queue.items.map((i) => i.collection).toSet(), {
      'users/u1/conversations/u1/messages',
    });
    expect(queue.items.every((i) => i.priority == 3), isTrue);
    expect(
      queue.items.every((i) => i.timestampFields.single == 'timestamp'),
      isTrue,
    );
    expect(queue.items.map((i) => i.docId), ['id0', 'id1']);
  });

  group('fallback reply (web wording, emotion calm)', () {
    Future<void> expectFallback(
      ConversationService s,
      MemoryMessageStore store,
    ) async {
      final r = await s.sendMessage(
        userId: 'u1',
        conversationId: 'u1',
        text: 'hello',
        context: const [],
      );
      expect(
        r.reply,
        "I'm having a little trouble connecting right now. I'm still here with you.",
      );
      expect(r.emotion, Emotion.calm);
      expect(r.latencyMs, isNull);
      final rows = await store.byConversation('u1');
      expect(rows.map((m) => m.sender), ['user', 'ai']);
      expect(rows.last.emotion, Emotion.calm);
    }

    test('no chat URL configured (Q2 open)', () async {
      final store = MemoryMessageStore();
      await expectFallback(
        _service(
          store: store,
          queue: RecordingSyncQueue(),
          api: ChatApiClient(baseUrl: ''),
        ),
        store,
      );
    });

    test('no Firebase user / ID token (Q1 open)', () async {
      final store = MemoryMessageStore();
      await expectFallback(
        _service(
          store: store,
          queue: RecordingSyncQueue(),
          api: _api([], body: _sse),
          token: null,
        ),
        store,
      );
    });

    test('server returns non-200', () async {
      final store = MemoryMessageStore();
      await expectFallback(
        _service(
          store: store,
          queue: RecordingSyncQueue(),
          api: _api([], status: 503, body: 'down'),
        ),
        store,
      );
    });
  });

  group('encrypted-only sync payloads (real KoiCryptoService)', () {
    final original = Cryptography.instance;
    setUpAll(() => KoiCryptography.install(useNative: false));
    tearDownAll(() {
      Cryptography.instance = original;
      CachingPbkdf2.clear();
    });

    test(
      'store and queue never hold plaintext; content decrypts back',
      () async {
        const plaintext = 'my private sentence ✦ اردو';
        final store = MemoryMessageStore();
        final queue = RecordingSyncQueue();
        final cipher = KoiMessageCipher(KoiCryptoService());
        await _service(
          store: store,
          queue: queue,
          api: ChatApiClient(baseUrl: ''), // → fallback reply
          cipher: cipher,
        ).sendMessage(
          userId: 'u1',
          conversationId: 'u1',
          text: plaintext,
          context: const [],
        );

        expect(queue.items, hasLength(2));
        for (final item in queue.items) {
          final content = item.data['content']! as String;
          expect(
            content,
            startsWith('v1:PBKDF2:${testCryptoContext.saltB64}:'),
          );
          expect(jsonEncode(item.data), isNot(contains('private sentence')));
          expect(jsonEncode(item.data), isNot(contains('trouble connecting')));
          // web field names on the record
          expect(
            item.data.keys,
            containsAll(<String>[
              'id',
              'conversationId',
              'sender',
              'content',
              'timestamp',
              'emotion',
              'emotion_confidence',
              'synced',
            ]),
          );
        }
        final rows = await store.byConversation('u1');
        expect(
          await cipher.decrypt(rows.first.content, testCryptoContext.secret),
          plaintext,
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  group('live server (127.0.0.1)', () {
    late FakeChatServer server;
    setUp(() async => server = await FakeChatServer.start());
    tearDown(() => server.close());

    ConversationService live({
      MemoryMessageStore? store,
      CrisisApiClient? crisis,
      Duration deadline = const Duration(seconds: 240),
    }) {
      var n = 0;
      return ConversationService(
        cryptoContext: (_) async => testCryptoContext,
        cipher: FakeCipher(),
        store: store ?? MemoryMessageStore(),
        syncQueue: RecordingSyncQueue(),
        api: ChatApiClient(baseUrl: server.base, deadline: deadline),
        idToken: () async => 'fake-test-token',
        crisis: crisis,
        newId: () => 'id${n++}',
      );
    }

    Future<SendMessageResult> send(
      ConversationService s, {
      ChatSessionState? session,
      ChatHandlers handlers = const ChatHandlers(),
      VoidCallback? onResolutionSent,
    }) => s.sendMessage(
      userId: 'u1',
      conversationId: 'u1',
      text: 'hi',
      context: const [],
      session: session,
      handlers: handlers,
      onResolutionSent: onResolutionSent,
    );

    test('the AI reply is saved as the full untrimmed text', () async {
      server.handler = (req, _) =>
          writeSse(req, okTurn(a: ' Breathe in.', b: ' Breathe out. '));
      final store = MemoryMessageStore();
      final cipher = FakeCipher();
      final r = await send(live(store: store));
      expect(r.reply, ' Breathe in. Breathe out. ');
      final ai = (await store.byConversation('u1')).last;
      expect(
        await cipher.decrypt(ai.content, ''),
        ' Breathe in. Breathe out. ',
      );
      expect(ai.emotion, Emotion.happy); // joy → happy
      expect(r.companionState!.intensity, 0.7);
    });

    test('client_event once, crisis_path once → onResolutionSent', () async {
      server.handler = (req, _) => writeSse(req, okTurn());
      final session = ChatSessionState()
        ..setClientEvent(ClientEvent.playbackDone)
        ..setCrisisPath(CrisisPath.reachedOut);
      var resolved = 0;
      final s = live();
      await send(s, session: session, onResolutionSent: () => resolved++);
      await send(s, session: session, onResolutionSent: () => resolved++);
      final first = server.requests[0].json;
      final second = server.requests[1].json;
      expect(first['client_event'], 'playback_done');
      expect(first['policy_event'], 'crisis_resolved');
      expect(first['crisis_path'], 'reached_out');
      expect(second['client_event'], 'none');
      expect(second['policy_event'], isNull);
      expect(second['exercise_state'], 'tok-1'); // echoed from `state`
      expect(resolved, 1);
    });

    test('kept for the next send when the request fails', () async {
      var fail = true;
      server.handler = (req, _) async {
        if (fail) {
          req.response.statusCode = 500;
          await req.response.close();
          return;
        }
        await writeSse(req, okTurn());
      };
      final session = ChatSessionState()
        ..setClientEvent(ClientEvent.playbackStopped)
        ..setCrisisPath(CrisisPath.saidButDidNot);
      var resolved = 0;
      final s = live();
      final r = await send(
        s,
        session: session,
        onResolutionSent: () => resolved++,
      );
      expect(r.isFallback, isTrue);
      expect(resolved, 0);
      fail = false;
      await send(s, session: session, onResolutionSent: () => resolved++);
      expect(server.requests[1].json['client_event'], 'playback_stopped');
      expect(server.requests[1].json['crisis_path'], 'said_but_did_not');
      expect(resolved, 1);
    });

    test('401 / 500 / network / timeout → fallback saved, code only', () async {
      Future<void> expectFallback(
        ConversationService s,
        String code,
        MemoryMessageStore store,
      ) async {
        final r = await send(s);
        expect(r.isFallback, isTrue);
        expect(r.reply, ConversationService.fallbackReply);
        expect(r.failureCode, code);
        final rows = await store.byConversation('u1');
        expect(rows.map((m) => m.sender), ['user', 'ai']);
      }

      for (final status in [401, 500]) {
        server.handler = (req, _) async {
          req.response
            ..statusCode = status
            ..write('{"detail":"PRIVATE"}');
          await req.response.close();
        };
        final store = MemoryMessageStore();
        await expectFallback(live(store: store), '$status', store);
      }

      server.handler = (req, _) async {
        await Future<void>.delayed(const Duration(seconds: 3));
        await req.response.close();
      };
      final slow = MemoryMessageStore();
      await expectFallback(
        live(store: slow, deadline: const Duration(milliseconds: 200)),
        'timeout',
        slow,
      );

      final offline = MemoryMessageStore();
      final s = live(store: offline);
      await server.close();
      await expectFallback(s, 'network', offline);
    });

    group('crisis service (C8 open)', () {
      late FakeChatServer crisisServer;
      setUp(() async {
        crisisServer = await FakeChatServer.start();
        crisisServer.handler = (req, _) async {
          req.response.write(
            '{"crisis_score":0.95,"risk_category":"CRITICAL",'
            '"modalities_used":["text"],"trigger_flags":[]}',
          );
          await req.response.close();
        };
        server.handler = (req, _) => writeSse(req, okTurn());
      });
      tearDown(() => crisisServer.close());

      test('not called when KOI_CRISIS_BASE is empty', () async {
        final risks = <RiskResult>[];
        await send(
          live(crisis: CrisisApiClient(baseUrl: '')),
          handlers: ChatHandlers(onRisk: risks.add),
        );
        await pumpEventQueue();
        expect(crisisServer.requests, isEmpty);
        expect(risks, isEmpty);
      });

      test('called once per turn when set; result → onRisk only', () async {
        final risks = <RiskResult>[];
        final s = live(crisis: CrisisApiClient(baseUrl: crisisServer.base));
        await send(s, handlers: ChatHandlers(onRisk: risks.add));
        await send(s, handlers: ChatHandlers(onRisk: risks.add));
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(crisisServer.requests, hasLength(2));
        expect(risks.map((r) => r.riskCategory), [
          RiskCategory.critical,
          RiskCategory.critical,
        ]);
        // Never put into the chat request (C5).
        expect(server.requests.first.json.containsKey('risk'), isFalse);
      });

      test('fails closed: an error gives no risk at all', () async {
        crisisServer.handler = (req, _) async {
          req.response.statusCode = 500;
          await req.response.close();
        };
        final risks = <RiskResult>[];
        await send(
          live(crisis: CrisisApiClient(baseUrl: crisisServer.base)),
          handlers: ChatHandlers(onRisk: risks.add),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(crisisServer.requests, hasLength(1));
        expect(risks, isEmpty);
      });
    });
  });
}
