import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/chat/chat_api.dart';
import 'package:koi_mobile/chat/chat_controller.dart';
import 'package:koi_mobile/chat/conversation_service.dart';
import 'package:koi_mobile/chat/message_record.dart';
import 'package:koi_mobile/core/emotion.dart';

import '../support/chat_fakes.dart';

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
    void Function(String chunk)? onDelta,
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
  test('optimistic user message + typing, then the reply', () async {
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

  test('blank input is ignored', () async {
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
    'context = the last 5 messages before the new one, web role names',
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
        ('model', 'r1'),
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
    'offline: queued (not sent), typing off; sent when back online',
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
    'history: decrypts stored rows in time order; undecryptable shown raw',
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
}
