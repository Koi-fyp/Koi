import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_flutter_lib/services/crypto_service.dart';
import 'package:koi_mobile/chat/chat_api.dart';
import 'package:koi_mobile/chat/conversation_service.dart';
import 'package:koi_mobile/chat/message_record.dart';
import 'package:koi_mobile/core/emotion.dart';
import 'package:koi_mobile/core/koi_cryptography.dart';

import '../support/chat_fakes.dart';

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
    '"companion_state": {"emotion": "sad"}}\n\n';

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
      expect(r.emotion, Emotion.sad);
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
      'conversations/u1/messages',
    });
    expect(queue.items.every((i) => i.priority == 3), isTrue);
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
}
