import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/core/key_value_store.dart';
import 'package:koi_mobile/core/sync_queue.dart';

class _Remote implements RemoteWriter {
  bool ready = false;
  String uid = 'u1';
  final failDocs = <String>{};
  Object Function() failWith = () => StateError('write failed');
  final written = <String>[];

  @override
  bool get isReady => ready;

  @override
  bool owns(SyncItem item) => item.ownerUid == uid;

  @override
  Future<void> write(SyncItem item) async {
    if (failDocs.contains(item.docId)) throw failWith();
    written.add(item.docId);
  }
}

SyncItem _item(String id, int priority, {String uid = 'u1'}) => SyncItem(
  collection: 'users/$uid/conversations/$uid/messages',
  docId: id,
  data: {'content': 'v1:PBKDF2:...', 'id': id},
  priority: priority,
);

void main() {
  test(
    'ATC-M14-12 not ready (Firebase not connected): persisted with a timestamp',
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

  test('ATC-M14-12 ready: written straight through; on failure queued', () async {
    final remote = _Remote()..ready = true;
    final q = PersistentSyncQueue(store: MemoryKeyValueStore(), remote: remote);
    remote.failDocs.add('bad');
    await q.enqueueAsync(_item('ok', 3));
    await q.enqueueAsync(_item('bad', 3));
    expect(remote.written, ['ok']);
    expect(q.pending.map((i) => i.docId), ['bad']);
  });

  test(
    'ATC-M14-12 permission-denied (rules not deployed): kept queued, never throws',
    () async {
      final remote = _Remote()
        ..ready = true
        ..failWith = () => FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
        );
      final q = PersistentSyncQueue(
        store: MemoryKeyValueStore(),
        remote: remote,
      );
      remote.failDocs.add('m1');
      await q.enqueueAsync(_item('m1', 3));
      await q.flush();
      await q.flush();
      expect(q.pending.map((i) => i.docId), ['m1']);
    },
  );

  test('ATC-M14-12 syncFailureReason: Firebase code, timeout, else the type only', () {
    expect(
      syncFailureReason(
        FirebaseException(plugin: 'p', code: 'permission-denied', message: 'x'),
      ),
      'permission-denied',
    );
    expect(syncFailureReason(TimeoutException('t')), 'timeout');
    expect(syncFailureReason(StateError('secret text')), 'StateError');
  });

  test('ATC-M14-13 flush: priority order (1 first), failures stay queued', () async {
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

  test(
    'ATC-M14-13 flush: equal priorities keep queue order (later merge lands last)',
    () async {
      final remote = _Remote();
      final q = PersistentSyncQueue(
        store: MemoryKeyValueStore(),
        remote: remote,
      );
      const ids = ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8'];
      for (final id in ids) {
        await q.enqueueAsync(_item(id, 4));
      }
      await q.enqueueAsync(_item('m', 3));
      remote.ready = true;
      await q.flush();
      expect(remote.written, ['m', ...ids]);
    },
  );

  test('ATC-M14-13 items for another uid are skipped and kept, not deleted', () async {
    final remote = _Remote()..ready = true;
    final q = PersistentSyncQueue(store: MemoryKeyValueStore(), remote: remote);
    await q.enqueueAsync(_item('old', 3, uid: 'debug-abc'));
    await q.enqueueAsync(
      const SyncItem(
        collection: 'conversations/debug-abc/messages', // pre-Prompt-15 path
        docId: 'legacy',
        data: {},
        priority: 3,
      ),
    );
    await q.enqueueAsync(_item('mine', 3));
    expect(remote.written, ['mine']);

    await q.flush();
    expect(remote.written, ['mine']);
    expect(q.pending.map((i) => i.docId), ['old', 'legacy']);
  });

  test('ATC-M14-13 ownerUid reads users/{uid} from the path', () {
    expect(_item('x', 3, uid: 'abc').ownerUid, 'abc');
    expect(SyncItem.saltCreateOnce('abc', 's').ownerUid, 'abc');
    expect(
      const SyncItem(
        collection: 'users',
        docId: 'abc',
        data: {},
        priority: 4,
      ).ownerUid,
      'abc',
    );
    expect(
      const SyncItem(
        collection: 'conversations/abc/messages',
        docId: 'm',
        data: {},
        priority: 3,
      ).ownerUid,
      isNull,
    );
  });

  test('ATC-M14-14 op and timestampFields survive persistence; old JSON = merge', () {
    SyncItem roundTrip(SyncItem i) => SyncItem.fromJson(
      (jsonDecode(jsonEncode(i.toJson())) as Map).cast<String, Object?>(),
    );

    final back = roundTrip(
      const SyncItem(
        collection: 'users/u1/conversations/u1/messages',
        docId: 'm',
        data: {'timestamp': '2026-10-17T10:00:00.000Z'},
        priority: 3,
        timestampFields: ['timestamp'],
      ),
    );
    expect(back.op, SyncOp.merge);
    expect(back.timestampFields, ['timestamp']);

    final salt = roundTrip(SyncItem.saltCreateOnce('u1', 's'));
    expect(salt.op, SyncOp.saltCreateOnce);
    expect(salt.priority, 4);

    final legacy = SyncItem.fromJson({
      'collection': 'users',
      'docId': 'u1',
      'data': <String, Object?>{},
      'priority': 4,
    });
    expect(legacy.op, SyncOp.merge);
    expect(legacy.timestampFields, isEmpty);
  });

  test('ATC-M14-15 coming back online triggers a flush (retry on reconnect)', () async {
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

  test('ATC-M14-14 corrupt stored queue reads as empty (web: JSON.parse catch → [])', () {
    final q = PersistentSyncQueue(
      store: MemoryKeyValueStore({'koi_sync_queue': '{not json'}),
      remote: _Remote(),
    );
    expect(q.pending, isEmpty);
  });
}
