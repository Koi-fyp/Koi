import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/avatar/avatar_state.dart';
import 'package:koi_mobile/chat/backend_warmup.dart';
import 'package:koi_mobile/chat/chat_api.dart';
import 'package:koi_mobile/chat/chat_controller.dart';
import 'package:koi_mobile/chat/chat_session_state.dart';
import 'package:koi_mobile/chat/conversation_service.dart';
import 'package:koi_mobile/chat/message_record.dart';
import 'package:koi_mobile/core/emotion.dart';
import 'package:koi_mobile/safety/safety_contract.dart';
import 'package:koi_mobile/safety/safety_controller.dart';

import '../support/chat_fakes.dart';
import '../support/fake_chat_server.dart';

/// Captures the context of each call and replies "r1", "r2", ...
class _ScriptedService extends ConversationService {
  _ScriptedService(MessageStore store)
    : super(
        cryptoContext: (_) async => testCryptoContext,
        cipher: FakeCipher(),
        store: store,
        syncQueue: RecordingSyncQueue(),
        api: ChatApiClient(baseUrl: ''),
        idToken: () async => 't',
      );

  final contexts = <List<ChatTurn>>[];

  @override
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
    contexts.add(context);
    return SendMessageResult(
      reply: 'r${contexts.length}',
      emotion: Emotion.happy,
      latencyMs: null,
    );
  }
}

void main() {
  test('ATC-M2-12 optimistic user message + typing, then the reply', () async {
    final service = _ScriptedService(MemoryMessageStore());
    final c = ChatController(
      uid: 'u1',
      service: service,
      isOnline: () async => true,
    );
    final typingSeen = <bool>[];
    c.addListener(() => typingSeen.add(c.isTyping));

    await c.send('  hello  ');
    expect(c.messages.map((m) => (m.sender, m.content)), [
      ('user', 'hello'),
      ('ai', 'r1'),
    ]);
    expect(typingSeen.first, isTrue); // optimistic + typing first
    expect(c.isTyping, isFalse);
    expect(c.currentEmotion, Emotion.happy);
    expect(c.conversationId, 'u1'); // Q5
  });

  test('ATC-M2-12 blank input is ignored', () async {
    final service = _ScriptedService(MemoryMessageStore());
    final c = ChatController(
      uid: 'u1',
      service: service,
      isOnline: () async => true,
    );
    await c.send('   ');
    expect(c.messages, isEmpty);
    expect(service.contexts, isEmpty);
  });

  test(
    'ATC-M2-13 context = the last 5 messages before the new one, web role names',
    () async {
      final service = _ScriptedService(MemoryMessageStore());
      final c = ChatController(
        uid: 'u1',
        service: service,
        isOnline: () async => true,
      );
      await c.send('m1'); // ctx []
      await c.send('m2'); // ctx [m1, r1]
      await c.send('m3'); // ctx [m1, r1, m2, r2]
      await c.send('m4'); // last 5 of 6

      expect(service.contexts[0], isEmpty);
      expect(service.contexts[1].map((t) => (t.role, t.content)), [
        ('user', 'm1'),
        ('assistant', 'r1'),
      ]);
      expect(service.contexts[3].map((t) => t.content), [
        'r1',
        'm2',
        'r2',
        'm3',
        'r3',
      ]);
    },
  );

  test(
    'ATC-M2-14 offline: queued (not sent), typing off; sent when back online',
    () async {
      final online = FakeOnlineStatus(online: false);
      final service = _ScriptedService(MemoryMessageStore());
      final c = ChatController(
        uid: 'u1',
        service: service,
        isOnline: online.check,
        onlineChanges: online.changes,
      );
      await c.send('while offline');
      expect(c.messages.map((m) => m.content), ['while offline']);
      expect(c.isTyping, isFalse);
      expect(c.offlineQueueLength, 1);
      expect(service.contexts, isEmpty);

      online.set(true);
      await pumpEventQueue();
      expect(service.contexts, hasLength(1));
      expect(c.messages.map((m) => m.content), ['while offline', 'r1']);
      expect(c.offlineQueueLength, 0);
    },
  );

  test(
    'ATC-M2-15 history: decrypts stored rows in time order; undecryptable shown raw',
    () async {
      final store = MemoryMessageStore();
      final cipher = FakeCipher();
      Future<void> put(
        String id,
        String sender,
        String content,
        int minute,
      ) async => store.put(
        MessageRecord(
          id: id,
          conversationId: 'u1',
          sender: sender,
          content: content,
          timestamp: DateTime.utc(2026, 1, 1, 0, minute),
          emotion: Emotion.calm,
          emotionConfidence: 1,
          synced: false,
        ),
      );
      await put('b', 'ai', await cipher.encrypt('second', 's', 'x'), 2);
      await put('a', 'user', await cipher.encrypt('first', 's', 'x'), 1);
      await put('c', 'ai', 'not-a-valid-payload', 3);
      await put(
        'other',
        'user',
        await cipher.encrypt('elsewhere', 's', 'x'),
        0,
      );
      await store.put(
        MessageRecord(
          id: 'x',
          conversationId: 'someone-else',
          sender: 'user',
          content: 'zzz',
          timestamp: DateTime.utc(2026),
          emotion: Emotion.neutral,
          emotionConfidence: 1,
          synced: false,
        ),
      );

      final c = ChatController(
        uid: 'u1',
        service: _ScriptedService(store),
        isOnline: () async => true,
      );
      await c.loadHistory();
      expect(c.messages.map((m) => m.content), [
        'elsewhere',
        'first',
        'second',
        'not-a-valid-payload',
      ]);
    },
  );

  test('ATC-M2-13 fallback replies are never sent back as history (B)', () async {
    final store = MemoryMessageStore();
    final cipher = FakeCipher();
    await store.put(
      MessageRecord(
        id: 'f',
        conversationId: 'u1',
        sender: 'ai',
        content: await cipher.encrypt(
          ConversationService.fallbackReply,
          's',
          'x',
        ),
        timestamp: DateTime.utc(2026),
        emotion: Emotion.calm,
        emotionConfidence: 1,
        synced: false,
      ),
    );
    final service = _ScriptedService(store);
    final c = ChatController(
      uid: 'u1',
      service: service,
      isOnline: () async => true,
    );
    await c.loadHistory();
    expect(c.messages.single.isFallback, isTrue); // still shown
    await c.send('m1');
    expect(service.contexts.single, isEmpty);
  });

  group('live stream wiring (127.0.0.1)', () {
    late FakeChatServer server;
    setUp(() async => server = await FakeChatServer.start());
    tearDown(() => server.close());

    ChatController controller({
      SafetyController? safety,
      BackendWarmup? backend,
      ChatSessionState? session,
    }) => ChatController(
      uid: 'u1',
      service: ConversationService(
        cryptoContext: (_) async => testCryptoContext,
        cipher: FakeCipher(),
        store: MemoryMessageStore(),
        syncQueue: RecordingSyncQueue(),
        api: ChatApiClient(baseUrl: server.base),
        idToken: () async => 'fake-test-token',
      ),
      isOnline: () async => true,
      safety: safety,
      backend: backend,
      session: session,
    );

    test('ATC-M2-16 deltas fill a live bubble that becomes the saved reply', () async {
      final gate = Completer<void>();
      server.handler = (req, _) async {
        req.response.headers.contentType = ContentType('text', 'event-stream');
        req.response.write(sseFrame('delta', {'text': 'Hel'}));
        await req.response.flush();
        await gate.future;
        req.response.write(
          sseFrame('delta', {'text': 'lo'}) +
              sseFrame('done', {'full_text': 'Hello'}),
        );
        await req.response.close();
      };
      final c = controller();
      final sending = c.send('hi');
      while (!c.isStreaming) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(c.messages.last.content, 'Hel');
      final liveId = c.messages.last.id;
      expect(c.isTyping, isTrue);

      // One message at a time.
      await c.send('second');
      expect(c.messages.where((m) => m.isUser), hasLength(1));

      gate.complete();
      await sending;
      expect(c.isStreaming, isFalse);
      expect(c.messages.map((m) => m.content), ['hi', 'Hello']);
      expect(c.messages.last.id, liveId);
    });

    test('ATC-M21-19 avatar: thinking → companion_state → speaking → idle', () async {
      server.handler = (req, _) => writeSse(
        req,
        sseFrame('companion_state', {'emotion': 'mystery', 'intensity': 9}) +
            sseFrame('companion_state', {'emotion': 'fun', 'intensity': 9}) +
            sseFrame('delta', {'text': 'a'}) +
            sseFrame('delta', {'text': 'b'}) +
            sseFrame('done', {'full_text': 'ab'}),
      );
      final c = controller();
      final events = <AvatarStateUpdate>[];
      final sub = c.avatarEvents.listen(
        (e) => events.add(e as AvatarStateUpdate),
      );
      await c.send('hi');
      await pumpEventQueue();
      await sub.cancel();
      expect(
        events.map(
          (e) => (e.emotion?.name, e.intensity, e.conversationState?.name),
        ),
        [
          (null, 0.0, 'thinking'),
          ('neutral', 1.0, null), // unknown → neutral, clamped
          ('fun', 1.0, null),
          (null, 0.0, 'speaking'),
          (null, 0.0, 'idle'),
        ],
      );
      expect(events.every((e) => e.sessionId == c.conversationId), isTrue);
    });

    test('ATC-M12-15 ui_action / handoff / risk reach SafetyController', () async {
      server.handler = (req, _) => writeSse(
        req,
        sseFrame('ui_action', {
              'name': 'start_breathing',
              'args': {
                'inhale_s': 4,
                'exhale_s': 6,
                'cycles': 2,
                'cue_audio': ['in', 'out'],
              },
            }) +
            sseFrame('delta', {'text': 'ok'}) +
            sseFrame('done', {'full_text': 'ok'}),
      );
      final safety = SafetyController();
      final c = controller(safety: safety);
      await c.send('breathe');
      expect(safety.breathing, isNotNull);

      server.handler = (req, _) => writeSse(
        req,
        sseFrame('delta', {'text': 'here'}) +
            sseFrame('handoff', {'to': 'crisis', 'reason': 'risk'}) +
            sseFrame('done', {'full_text': 'here'}),
      );
      await c.send('one');
      await c.send('two'); // the handoff repeats every turn
      expect(safety.crisisCount, 1);
      expect(safety.breathing, isNull); // crisis stopped the animation
    });

    test('ATC-M12-15 risk unavailable never shows anything', () async {
      server.handler = (req, _) => writeSse(
        req,
        sseFrame('delta', {'text': 'ok'}) +
            sseFrame('risk', {'status': 'unavailable'}) +
            sseFrame('done', {
              'full_text': 'ok',
              'risk': {'status': 'unavailable'},
            }),
      );
      final safety = SafetyController();
      await controller(safety: safety).send('hi');
      expect(safety.crisis, isNull);
      expect(safety.crisisCount, 0);
    });

    test('ATC-M12-15 crisis path sent once, then crisisResolutionSent()', () async {
      server.handler = (req, _) => writeSse(
        req,
        sseFrame('handoff', {'to': 'crisis', 'reason': 'r'}) +
            sseFrame('delta', {'text': 'ok'}) +
            sseFrame('done', {'full_text': 'ok'}),
      );
      final session = ChatSessionState();
      final safety = SafetyController(
        onCrisisPath: session.setCrisisPath,
        onClientEvent: session.setClientEvent,
      );
      final c = controller(safety: safety, session: session);
      await c.send('one');
      expect(safety.crisis, isNotNull);
      safety.chooseCrisisPath(CrisisPath.reachedOut);
      expect(safety.resolutionPending, isTrue);

      server.handler = (req, _) => writeSse(
        req,
        sseFrame('delta', {'text': 'ok'}) +
            sseFrame('done', {'full_text': 'ok'}),
      );
      await c.send('two');
      expect(server.requests[1].json['crisis_path'], 'reached_out');
      expect(server.requests[1].json['policy_event'], 'crisis_resolved');
      expect(safety.resolutionPending, isFalse);
      await c.send('three');
      expect(server.requests[2].json['crisis_path'], isNull);
    });

    test('ATC-M2-23 waking after the threshold; cleared on the first event', () async {
      final gate = Completer<void>();
      server.handler = (req, _) async {
        await gate.future;
        await writeSse(req, okTurn());
      };
      final backend = BackendWarmup(
        chatHealth: null,
        wakingAfter: const Duration(milliseconds: 50),
      );
      final c = controller(backend: backend);
      final sending = c.send('hi');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(c.backendStatus, BackendStatus.waking);
      gate.complete();
      await sending;
      expect(c.backendStatus, BackendStatus.ready);
    });

    test('ATC-M2-23 first send held until chat /health 200, then released; later '
        'sends not held', () async {
      server.handler = (req, _) => writeSse(req, okTurn());
      final health = Completer<bool>();
      final backend = BackendWarmup(chatHealth: (_) => health.future)..warmUp();
      final c = controller(backend: backend);
      final first = c.send('hi');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(server.requests, isEmpty); // held
      expect(c.isTyping, isTrue);
      expect(c.messages.single.content, 'hi'); // shown right away
      expect(c.backendStatus, BackendStatus.waking);
      health.complete(true);
      await first;
      expect(server.requests, hasLength(1));
      expect(c.backendStatus, BackendStatus.ready);

      await c.send('again'); // not held

      expect(server.requests, hasLength(2));
    });

    test('ATC-M2-23 first send released when the warm-up gives up', () async {
      server.handler = (req, _) => writeSse(req, okTurn());
      var now = DateTime(2026, 10, 18, 12);
      final backend = BackendWarmup(
        chatHealth: (_) async => false,
        now: () => now,
        delay: (d) async => now = now.add(d),
      )..warmUp();
      final c = controller(backend: backend);
      await c.send('hi');
      expect(server.requests, hasLength(1));
    });
  });
}
