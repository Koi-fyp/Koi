import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_flutter_lib/services/crypto_service.dart';
import 'package:koi_mobile/chat/backend_warmup.dart';
import 'package:koi_mobile/chat/chat_api.dart';
import 'package:koi_mobile/chat/chat_controller.dart';
import 'package:koi_mobile/chat/conversation_service.dart';
import 'package:koi_mobile/chat/message_record.dart';
import 'package:koi_mobile/core/koi_cryptography.dart';

import '../support/chat_fakes.dart';
import '../support/fake_chat_server.dart';

const _token = 'fake-test-token-not-real';

/// ASCII only: FakeChatServer decodes request bodies as UTF-8.
const _clipText = 'RIFF-fake-wav-clip';

/// The text and headers of one multipart part named [name].
({String headers, String body})? _part(SeenRequest seen, String name) {
  final boundary = RegExp(r'boundary=(.+)$')
      .firstMatch(seen.header('content-type')!)!
      .group(1)!;
  for (final raw in seen.body.split('--$boundary')) {
    final split = raw.indexOf('\r\n\r\n');
    if (split < 0) continue;
    final headers = raw.substring(0, split);
    if (!headers.contains('name="$name"')) continue;
    var body = raw.substring(split + 4);
    if (body.endsWith('\r\n')) body = body.substring(0, body.length - 2);
    return (headers: headers, body: body);
  }
  return null;
}

String _audioTurn({String transcript = 'I feel tired'}) =>
    sseFrame('transcript', {'text': transcript, 'language': 'en'}) +
    okTurn(a: 'That sounds', b: ' hard.');

/// Plays an audio turn through the handlers, or fails.
class _AudioApi extends ChatApiClient {
  _AudioApi() : super(baseUrl: 'https://chat.example.test');

  String? transcript = 'I feel tired';
  String reply = 'That sounds hard.';

  /// Thrown before any event (e.g. 422) or, with [failAfterTranscript],
  /// after the transcript.
  Object? error;
  bool failAfterTranscript = false;
  final List<(Map<String, Object?>, AudioUpload?)> calls = [];

  @override
  Future<ChatStreamResult> streamChat({
    required String idToken,
    required Map<String, Object?> body,
    ChatHandlers handlers = const ChatHandlers(),
    AudioUpload? audio,
  }) async {
    calls.add((body, audio));
    final e = error;
    if (e != null && !failAfterTranscript) throw e;
    final t = transcript;
    if (t != null) handlers.onTranscript?.call(t);
    if (e != null) throw e;
    handlers.onEvent?.call('delta');
    handlers.onDelta?.call(reply);
    return ChatStreamResult(
      fullText: reply,
      companionState: CompanionState.fallback,
      latencyMs: 5,
      exerciseStateChanged: false,
      exerciseState: null,
    );
  }
}

void main() {
  late Directory dir;
  late String clip;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('koi_mic_test');
    clip = '${dir.path}${Platform.pathSeparator}clip.wav';
    await File(clip).writeAsString(_clipText);
  });
  tearDown(() => dir.delete(recursive: true));

  group('ATC-M3-24 transport (multipart)', () {
    late FakeChatServer server;
    setUp(() async => server = await FakeChatServer.start());
    tearDown(() => server.close());

    test('payload JSON field + audio file field; transcript first', () async {
      server.handler = (req, _) => writeSse(req, _audioTurn());
      final events = <String>[];
      String? heard;
      final body = chatRequestBody(
        message: '',
        sessionHistory: const [ChatTurn(role: 'user', content: 'earlier')],
      );
      final r = await ChatApiClient(baseUrl: server.base).streamChat(
        idToken: _token,
        body: body,
        audio: AudioUpload(clip),
        handlers: ChatHandlers(
          onEvent: events.add,
          onTranscript: (t) => heard = t,
        ),
      );

      final seen = server.requests.single;
      expect(seen.method, 'POST');
      expect(seen.uri.path, '/api/v1/chat');
      expect(seen.header('content-type'), startsWith('multipart/form-data'));
      expect(seen.header('authorization'), 'Bearer $_token');
      expect(seen.header('accept'), 'text/event-stream');

      final payload = _part(seen, 'payload')!;
      // A plain text field (chat_core.py: form.get("payload") must be str).
      expect(payload.headers, isNot(contains('filename=')));
      expect(jsonDecode(payload.body), body);
      expect((jsonDecode(payload.body) as Map)['message'], '');

      final audio = _part(seen, 'audio')!;
      expect(audio.headers, contains('filename="voice.wav"'));
      expect(audio.headers.toLowerCase(), contains('content-type: audio/wav'));
      expect(audio.body, _clipText);

      expect(heard, 'I feel tired');
      expect(events.first, 'transcript');
      expect(r.fullText, 'That sounds hard.');
    });

    test(
      '303 poll hop is a GET without the body; stream still parsed',
      () async {
        server.handler = (req, seen) async {
          if (seen.uri.path == '/api/v1/chat') {
            req.response
              ..statusCode = 303
              ..headers.set('location', '/poll/1');
            await req.response.close();
          } else {
            await writeSse(req, _audioTurn());
          }
        };
        String? heard;
        final r = await ChatApiClient(baseUrl: server.base).streamChat(
          idToken: _token,
          body: chatRequestBody(message: '', sessionHistory: const []),
          audio: AudioUpload(clip),
          handlers: ChatHandlers(onTranscript: (t) => heard = t),
        );
        expect(server.requests.map((s) => s.method), ['POST', 'GET']);
        expect(server.requests.last.body, isEmpty);
        expect(heard, 'I feel tired');
        expect(r.fullText, 'That sounds hard.');
      },
    );

    test('422 → ChatApiException(422), no events', () async {
      server.handler = (req, _) async {
        req.response.statusCode = 422;
        req.response.write(
          '{"detail":"audio transcription did not complete'
          ' in time"}',
        );
        await req.response.close();
      };
      var transcripts = 0;
      await expectLater(
        ChatApiClient(baseUrl: server.base).streamChat(
          idToken: _token,
          body: chatRequestBody(message: '', sessionHistory: const []),
          audio: AudioUpload(clip),
          handlers: ChatHandlers(onTranscript: (_) => transcripts++),
        ),
        throwsA(isA<ChatApiException>().having((e) => e.code, 'code', '422')),
      );
      expect(transcripts, 0);
    });

    test('text turns are still JSON', () async {
      server.handler = (req, _) => writeSse(req, okTurn());
      await ChatApiClient(baseUrl: server.base).streamChat(
        idToken: _token,
        body: chatRequestBody(message: 'hi', sessionHistory: const []),
      );
      expect(server.requests.single.header('content-type'), 'application/json');
      expect(server.requests.single.json['message'], 'hi');
    });
  });

  group('ATC-M3-25 ConversationService.sendAudio', () {
    late MemoryMessageStore store;
    late RecordingSyncQueue queue;
    late _AudioApi api;
    late FakeCipher cipher;

    ConversationService service() {
      var n = 0;
      return ConversationService(
        cryptoContext: (_) async => testCryptoContext,
        cipher: cipher,
        store: store,
        syncQueue: queue,
        api: api,
        idToken: () async => _token,
        newId: () => 'id-${n++}',
      );
    }

    setUp(() {
      store = MemoryMessageStore();
      queue = RecordingSyncQueue();
      api = _AudioApi();
      cipher = FakeCipher();
    });

    Future<AudioSendResult> send({bool saveTranscript = true}) =>
        service().sendAudio(
          userId: 'u1',
          conversationId: 'u1',
          audio: AudioUpload(clip),
          context: const [ChatTurn(role: 'user', content: 'before')],
          saveTranscript: saveTranscript,
        );

    test('transcript saved like a typed message, then the reply', () async {
      final r = await send();
      expect(r.ok, isTrue);
      expect(r.transcriptSaved, isTrue);
      expect(r.reply, 'That sounds hard.');

      final (body, audio) = api.calls.single;
      expect(body['message'], '');
      expect(body['session_history'], [
        {'role': 'user', 'content': 'before'},
      ]);
      expect(audio!.path, clip);

      final rows = await store.byConversation('u1');
      expect(rows.map((r) => r.sender), ['user', 'ai']);
      // Encrypted at rest (CSE), same path as typed messages.
      expect(rows.first.content, isNot(contains('I feel tired')));
      expect(await cipher.decrypt(rows.first.content, 'x'), 'I feel tired');
      expect(queue.items, hasLength(2));
      expect(
        queue.items.first.collection,
        'users/u1/conversations/u1/messages',
      );
      expect(queue.items.first.data['content'], rows.first.content);
    });

    for (final (name, error, code) in [
      ('422', const ChatApiException('422'), '422'),
      ('timeout', const ChatTimeoutException(), 'timeout'),
      ('network', const ChatApiException('network'), 'network'),
    ]) {
      test('$name → error code, nothing saved, no fallback reply', () async {
        api.error = error;
        final r = await send();
        expect(r.failureCode, code);
        expect(r.reply, isNull);
        expect(r.transcriptSaved, isFalse);
        expect(store.rows, isEmpty);
        expect(queue.items, isEmpty);
      });
    }

    test('timeout after the transcript: only the transcript is kept', () async {
      api
        ..error = const ChatTimeoutException()
        ..failAfterTranscript = true;
      final r = await send();
      expect(r.failureCode, 'timeout');
      expect(r.transcriptSaved, isTrue);
      final rows = await store.byConversation('u1');
      expect(rows.map((r) => r.sender), ['user']);
      expect(
        rows.where((r) => r.content.contains('trouble connecting')),
        isEmpty,
      );
    });

    test('Retry (saveTranscript: false) does not save it again', () async {
      final r = await send(saveTranscript: false);
      expect(r.ok, isTrue);
      expect(r.transcriptSaved, isFalse);
      final rows = await store.byConversation('u1');
      expect(rows.map((r) => r.sender), ['ai']);
    });

    test('no / blank transcript → no_transcript, nothing saved', () async {
      for (final t in [null, '   ']) {
        api.transcript = t;
        final r = await send();
        expect(r.failureCode, ChatApiException.noTranscript);
        expect(store.rows, isEmpty);
      }
    });

    test('warm-up failed → warmup, nothing sent', () async {
      final r = await service().sendAudio(
        userId: 'u1',
        conversationId: 'u1',
        audio: AudioUpload(clip),
        context: const [],
        beforeRequest: () async => false,
      );
      expect(r.failureCode, 'warmup');
      expect(api.calls, isEmpty);
      expect(store.rows, isEmpty);
    });
  });

  group('encrypted sync payload for a voice turn (real KoiCryptoService)', () {
    final original = Cryptography.instance;
    setUpAll(() => KoiCryptography.install(useNative: false));
    tearDownAll(() {
      Cryptography.instance = original;
      CachingPbkdf2.clear();
    });

    test(
      'ATC-M3-34 mic transcript reaches the Firestore sync queue encrypted; '
      'no plaintext in the store or the queue',
      () async {
        const transcript = 'my private voice note ✦ اردو';
        final store = MemoryMessageStore();
        final queue = RecordingSyncQueue();
        final cipher = KoiMessageCipher(KoiCryptoService());
        final api = _AudioApi()..transcript = transcript;
        var n = 0;
        final r =
            await ConversationService(
              cryptoContext: (_) async => testCryptoContext,
              cipher: cipher,
              store: store,
              syncQueue: queue,
              api: api,
              idToken: () async => _token,
              newId: () => 'id-${n++}',
            ).sendAudio(
              userId: 'u1',
              conversationId: 'u1',
              audio: AudioUpload(clip),
              context: const [],
            );
        expect(r.ok, isTrue);
        expect(r.transcriptSaved, isTrue);

        // Transcript (user) and reply (ai), both queued for Firestore.
        expect(queue.items, hasLength(2));
        expect(queue.items.map((i) => i.data['sender']), ['user', 'ai']);
        for (final item in queue.items) {
          expect(item.collection, 'users/u1/conversations/u1/messages');
          expect(
            item.data['content'],
            startsWith('v1:PBKDF2:${testCryptoContext.saltB64}:'),
          );
          expect(jsonEncode(item.data), isNot(contains('private voice')));
          expect(jsonEncode(item.data), isNot(contains('sounds hard')));
        }
        final rows = await store.byConversation('u1');
        expect(rows.first.content, queue.items.first.data['content']);
        expect(
          await cipher.decrypt(rows.first.content, testCryptoContext.secret),
          transcript,
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  group('ATC-M3-26 ChatController.sendVoice', () {
    late _AudioApi api;
    late MemoryMessageStore store;

    ChatController controller({BackendWarmup? backend}) {
      var n = 0;
      return ChatController(
        uid: 'u1',
        service: ConversationService(
          cryptoContext: (_) async => testCryptoContext,
          cipher: FakeCipher(),
          store: store,
          syncQueue: RecordingSyncQueue(),
          api: api,
          idToken: () async => _token,
        ),
        isOnline: () async => true,
        backend: backend,
        newId: () => 'c-${n++}',
      );
    }

    setUp(() {
      api = _AudioApi();
      store = MemoryMessageStore();
    });

    test('transcript becomes the user message, then the reply', () async {
      final chat = controller();
      final seen = <List<String>>[];
      chat.addListener(
        () => seen.add([for (final m in chat.messages) m.content]),
      );
      final r = await chat.sendVoice(AudioUpload(clip));
      expect(r.ok, isTrue);
      expect(chat.messages.map((m) => (m.sender, m.content)), [
        ('user', 'I feel tired'),
        ('ai', 'That sounds hard.'),
      ]);
      // The transcript showed before the reply streamed.
      expect(seen, anyElement(equals(['I feel tired'])));
      expect(chat.isTyping, isFalse);
    });

    test('422: no message at all, no fallback reply', () async {
      api.error = const ChatApiException('422');
      final chat = controller();
      final r = await chat.sendVoice(AudioUpload(clip));
      expect(r.failureCode, '422');
      expect(chat.messages, isEmpty);
      expect(chat.isTyping, isFalse);
    });

    test('Retry after a saved transcript: one user bubble only', () async {
      api
        ..error = const ChatTimeoutException()
        ..failAfterTranscript = true;
      final chat = controller();
      final first = await chat.sendVoice(AudioUpload(clip));
      expect(first.transcriptSaved, isTrue);
      expect(chat.messages.map((m) => m.sender), ['user']);

      api.error = null;
      final second = await chat.sendVoice(
        AudioUpload(clip),
        saveTranscript: false,
      );
      expect(second.ok, isTrue);
      expect(chat.messages.map((m) => m.sender), ['user', 'ai']);
      expect((await store.byConversation('u1')).map((r) => r.sender), [
        'user',
        'ai',
      ]);
    });

    test('offline: nothing queued, offline code', () async {
      final chat = ChatController(
        uid: 'u1',
        service: ConversationService(
          cryptoContext: (_) async => testCryptoContext,
          cipher: FakeCipher(),
          store: store,
          syncQueue: RecordingSyncQueue(),
          api: api,
          idToken: () async => _token,
        ),
        isOnline: () async => false,
      );
      final r = await chat.sendVoice(AudioUpload(clip));
      expect(r.failureCode, 'offline');
      expect(api.calls, isEmpty);
      expect(chat.offlineQueueLength, 0);
    });

    test('waits for chat AND crisis /health 200 before the upload', () async {
      final chatHealth = Completer<bool>();
      final crisisHealth = Completer<bool>();
      final warmup = BackendWarmup(
        chatHealth: (_) => chatHealth.future,
        crisisHealth: (_) => crisisHealth.future,
      );
      final chat = controller(backend: warmup);
      final done = chat.sendVoice(AudioUpload(clip));
      await pumpEventQueue();
      expect(warmup.holdingAudio, isTrue);
      expect(chat.holdingAudio, isTrue);
      expect(api.calls, isEmpty);

      chatHealth.complete(true);
      await pumpEventQueue();
      expect(api.calls, isEmpty, reason: 'crisis not warm yet');

      crisisHealth.complete(true);
      final r = await done;
      expect(r.ok, isTrue);
      expect(api.calls, hasLength(1));
      expect(warmup.holdingAudio, isFalse);
      warmup.dispose();
    });
  });

  group('ATC-M3-27 BackendWarmup.holdForAudio', () {
    test('crisis never 200 within the limit → false, chat untouched', () async {
      var now = DateTime(2026, 10, 18);
      final warmup = BackendWarmup(
        chatHealth: (_) async => true,
        crisisHealth: (_) async => false,
        limit: const Duration(seconds: 10),
        now: () => now,
        delay: (d) async => now = now.add(d),
      );
      expect(await warmup.holdForAudio(), isFalse);
      expect(warmup.status, BackendStatus.ready);
      warmup.dispose();
    });

    test('already warm → no new /health calls', () async {
      var calls = 0;
      final warmup = BackendWarmup(
        chatHealth: (_) async {
          calls++;
          return true;
        },
        crisisHealth: (_) async {
          calls++;
          return true;
        },
      );
      warmup.warmUp();
      await pumpEventQueue();
      expect(calls, 2);
      expect(await warmup.holdForAudio(), isTrue);
      warmup.prepareAudio();
      expect(calls, 2);
      warmup.dispose();
    });

    test('no crisis base → only chat is waited for', () async {
      final warmup = BackendWarmup(chatHealth: (_) async => true);
      expect(await warmup.holdForAudio(), isTrue);
      warmup.dispose();
    });
  });
}
