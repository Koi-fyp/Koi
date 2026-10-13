import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/core/key_value_store.dart';
import 'package:koi_mobile/core/sync_queue.dart';

class _Remote implements RemoteWriter {
  bool ready = false;
  final failDocs = <String>{};
  final written = <String>[];

  @override
  bool get isReady => ready;

  @override
  Future<void> setMerge(String c, String d, Map<String, Object?> data) async {
    if (failDocs.contains(d)) throw StateError('write failed');
    written.add(d);
  }
}

SyncItem _item(String id, int priority) => SyncItem(
  collection: 'conversations/u1/messages',
  docId: id,
  data: {'content': 'v1:PBKDF2:...', 'id': id},
  priority: priority,
);

void main() {
  test(
    'not ready (Firebase not connected): persisted with a timestamp',
    () async {
      final kv = MemoryKeyValueStore();
      final q = PersistentSyncQueue(
        store: kv,
        remote: _Remote(),
        now: () => 1234,
      );
      await q.enqueueAsync(_item('a', 3));
      await q.enqueueAsync(_item('b', 1));

      expect(kv.values.keys, ['koi_sync_queue']); // sync.ts QUEUE_KEY
      expect(q.pending.map((i) => i.docId), ['a', 'b']);
      expect(q.pending.every((i) => i.timestamp == 1234), isTrue);

      // A fresh queue on the same storage sees the same items (persistence).
      final q2 = PersistentSyncQueue(store: kv, remote: _Remote());
      expect(q2.pending, hasLength(2));
    },
  );

  test('ready: written straight through; on failure queued', () async {
    final remote = _Remote()..ready = true;
    final q = PersistentSyncQueue(store: MemoryKeyValueStore(), remote: remote);
    remote.failDocs.add('bad');
    await q.enqueueAsync(_item('ok', 3));
    await q.enqueueAsync(_item('bad', 3));
    expect(remote.written, ['ok']);
    expect(q.pending.map((i) => i.docId), ['bad']);
  });

  test('flush: priority order (1 first), failures stay queued', () async {
    final remote = _Remote();
    final q = PersistentSyncQueue(store: MemoryKeyValueStore(), remote: remote);
    await q.enqueueAsync(_item('user', 4));
    await q.enqueueAsync(_item('msg', 3));
    await q.enqueueAsync(_item('crisis', 1));
    await q.enqueueAsync(_item('mood', 2));

    await q.flush(); // not ready: no-op
    expect(remote.written, isEmpty);
    expect(q.pending, hasLength(4));

    remote
      ..ready = true
      ..failDocs.add('msg');
    await q.flush();
    expect(remote.written, ['crisis', 'mood', 'user']);
    expect(q.pending.map((i) => i.docId), ['msg']);
  });

  test('coming back online triggers a flush (retry on reconnect)', () async {
    final remote = _Remote();
    final online = StreamController<bool>();
    final q = PersistentSyncQueue(
      store: MemoryKeyValueStore(),
      remote: remote,
      onlineChanges: online.stream,
    );
    await q.enqueueAsync(_item('m1', 3));
    remote.ready = true;

    online.add(false);
    await pumpEventQueue();
    expect(remote.written, isEmpty);

    online.add(true);
    await pumpEventQueue();
    expect(remote.written, ['m1']);
    expect(q.pending, isEmpty);
    await q.dispose();
  });

  test('corrupt stored queue reads as empty (web: JSON.parse catch → [])', () {
    final q = PersistentSyncQueue(
      store: MemoryKeyValueStore({'koi_sync_queue': '{not json'}),
      remote: _Remote(),
    );
    expect(q.pending, isEmpty);
  });
}
