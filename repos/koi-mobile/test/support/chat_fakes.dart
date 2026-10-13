import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koi_mobile/app/providers.dart';
import 'package:koi_mobile/chat/chat_api.dart';
import 'package:koi_mobile/chat/conversation_service.dart';
import 'package:koi_mobile/chat/message_record.dart';
import 'package:koi_mobile/core/crypto_context.dart';
import 'package:koi_mobile/core/sync_queue.dart';

/// Scriptable connectivity.
class FakeOnlineStatus implements OnlineStatus {
  FakeOnlineStatus({this.online = true});
  bool online;
  final _changes = StreamController<bool>.broadcast();

  void set(bool value) {
    online = value;
    _changes.add(value);
  }

  @override
  Future<bool> check() async => online;
  @override
  Stream<bool> get changes => _changes.stream;
}

/// Records enqueued items (never writes anywhere).
class RecordingSyncQueue implements SyncQueue {
  final items = <SyncItem>[];
  @override
  void enqueue(SyncItem item) => items.add(item);
}

/// Cheap, reversible stand-in for KoiCryptoService in widget tests.
/// The output never contains the plaintext verbatim.
class FakeCipher implements MessageCipher {
  int encryptCalls = 0;

  @override
  Future<String> encrypt(
    String plaintext,
    String secret,
    String saltB64,
  ) async {
    encryptCalls++;
    return 'v1:FAKE:${base64Encode(utf8.encode(plaintext).reversed.toList())}';
  }

  @override
  Future<String> decrypt(String payload, String secret) async {
    if (!payload.startsWith('v1:FAKE:')) throw const FormatException('bad');
    return utf8.decode(base64Decode(payload.substring(8)).reversed.toList());
  }
}

const testCryptoContext = CryptoContext(
  secret: 'test-secret',
  saltB64: 'AAECAwQFBgcICQoLDA0ODw==',
);

/// Overrides for every chat provider: no network, no secure storage.
List<Override> chatOverrides({
  FakeOnlineStatus? online,
  MessageStore? store,
  SyncQueue? queue,
  MessageCipher? cipher,
  ChatApiClient? api,
}) => [
  onlineStatusProvider.overrideWithValue(online ?? FakeOnlineStatus()),
  messageStoreProvider.overrideWithValue(store ?? MemoryMessageStore()),
  syncQueueProvider.overrideWithValue(queue ?? RecordingSyncQueue()),
  messageCipherProvider.overrideWithValue(cipher ?? FakeCipher()),
  chatApiProvider.overrideWithValue(api ?? ChatApiClient(baseUrl: '')),
  cryptoContextGetterProvider.overrideWithValue(
    (uid) async => testCryptoContext,
  ),
];
