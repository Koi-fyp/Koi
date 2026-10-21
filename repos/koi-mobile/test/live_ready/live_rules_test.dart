import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_flutter_lib/services/crypto_service.dart';
import 'package:koi_mobile/account/account_controller.dart';
import 'package:koi_mobile/account/account_migration.dart';
import 'package:koi_mobile/chat/chat_api.dart';
import 'package:koi_mobile/chat/conversation_service.dart';
import 'package:koi_mobile/chat/message_record.dart';
import 'package:koi_mobile/checkins/checkin_store.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/core/crypto_context.dart';
import 'package:koi_mobile/core/emotion.dart';
import 'package:koi_mobile/core/firestore/firestore_remote_writer.dart';
import 'package:koi_mobile/core/firestore/live_rules.dart';
import 'package:koi_mobile/core/firestore/profile_sync.dart';
import 'package:koi_mobile/core/firestore/user_document_store.dart';
import 'package:koi_mobile/core/key_value_store.dart';
import 'package:koi_mobile/core/koi_cryptography.dart';
import 'package:koi_mobile/core/onboarding_store.dart';
import 'package:koi_mobile/core/sync_queue.dart';
import 'package:koi_mobile/onboarding/onboarding_service.dart';
import 'package:koi_mobile/settings/settings_prefs.dart';

import '../support/chat_fakes.dart';
import '../support/mob1_fakes.dart';

const _uid = 'u1';

/// A ciphertext of the live format: salt 16 B, nonce 12 B, ct+tag 16 B.
const _ct =
    'v1:PBKDF2:AAAAAAAAAAAAAAAAAAAAAA==:AAAAAAAAAAAAAAAA:'
    'AAAAAAAAAAAAAAAAAAAAAA==';

Map<String, Object?> _valid() => {
  'id': 'm1',
  'conversationId': _uid,
  'sender': 'user',
  'content': _ct,
  'timestamp': '2026-10-20T09:00:00.000Z',
  'emotion': 'neutral',
  'emotion_confidence': 1,
  'synced': false,
};

SyncItem _message(Map<String, Object?> data, {String docId = 'm1'}) => SyncItem(
  collection: ConversationService.messagesCollection(_uid, _uid),
  docId: docId,
  data: data,
  priority: 3,
  timestampFields: const ['timestamp'],
);

final DateTime _now = DateTime.utc(2026, 10, 20, 9, 1);

/// Every message write must carry EXACTLY the live key set with the live
/// types, written as Firestore would receive it.
void _expectLiveMessage(SyncItem item) {
  final d = firestoreData(item);
  expect(d.keys.toSet(), liveMessageKeys, reason: 'exact key set');
  final path = item.collection.split('/');
  expect(path, hasLength(5));
  expect(path[0], 'users');
  expect(path[2], 'conversations');
  expect(path[4], 'messages');
  expect(d['id'], item.docId);
  expect(d['conversationId'], path[3]);
  expect(liveMessageSenders, contains(d['sender']));
  expect(d['content'], matches(liveCiphertextPattern));
  expect((d['content']! as String).length, lessThanOrEqualTo(65536));
  expect(d['timestamp'], isA<Timestamp>());
  expect(d['emotion'], isA<String>());
  expect((d['emotion']! as String).length, lessThanOrEqualTo(32));
  expect(d['emotion_confidence'], isA<num>());
  expect(d['emotion_confidence'], inInclusiveRange(0, 1));
  expect(d['synced'], isA<bool>());
  expect(liveRulesViolation(item), isNull);
}

/// Acks every write; records them.
class _AckUploader implements MigrationUploader {
  final uploads = <SyncItem>[];
  @override
  Future<bool> writeNow(SyncItem item) async {
    uploads.add(item);
    return true;
  }

  @override
  Future<int> removeWhere(bool Function(SyncItem item) test) async => 0;
}

/// Throws [SyncRejected] for [rejectIds] (the server refused them for good).
class _RejectingUploader extends _AckUploader {
  _RejectingUploader(this.rejectIds);
  final Set<String> rejectIds;
  final attempts = <String>[];
  @override
  Future<bool> writeNow(SyncItem item) async {
    attempts.add(item.docId);
    if (rejectIds.contains(item.docId)) {
      throw const SyncRejected('permission-denied');
    }
    return super.writeNow(item);
  }
}

class _Remote implements RemoteWriter {
  _Remote(this.fail);
  Object? Function(SyncItem item) fail;
  final written = <String>[];
  int calls = 0;
  @override
  bool get isReady => true;
  @override
  bool owns(SyncItem item) => item.ownerUid == _uid;
  @override
  Future<void> write(SyncItem item) async {
    calls++;
    final e = fail(item);
    if (e != null) throw e;
    written.add(item.docId);
  }
}

FirebaseException _fb(String code) =>
    FirebaseException(plugin: 'cloud_firestore', code: code);

MessageRecord _record(String id, String content) => MessageRecord(
  id: id,
  conversationId: _uid,
  sender: 'user',
  content: content,
  timestamp: DateTime.utc(2026, 10, 20, 8),
  emotion: Emotion.neutral,
  emotionConfidence: 1,
  synced: false,
);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('LIVE-01 every Firestore write mobile makes matches the live rules', () {
    final original = Cryptography.instance;
    setUpAll(() => KoiCryptography.install(useNative: false));
    tearDownAll(() {
      Cryptography.instance = original;
      CachingPbkdf2.clear();
    });

    test(
      'chat messages, link re-uploads and claim copies (real KoiCryptoService)',
      () async {
        final cipher = KoiMessageCipher(KoiCryptoService());
        final store = MemoryMessageStore();
        final queue = RecordingSyncQueue();
        var n = 0;
        final service = ConversationService(
          cryptoContext: (_) async => testCryptoContext,
          cipher: cipher,
          store: store,
          syncQueue: queue,
          api: ChatApiClient(baseUrl: ''), // → the fallback reply
          idToken: () async => 'tok',
          newId: () => 'id${n++}',
        );
        // A long message (about 30 KB) still fits the 64 KB limit.
        await service.sendMessage(
          userId: _uid,
          conversationId: _uid,
          text: 'long ✦ اردو ${'x' * 30000}',
          context: const [],
        );
        expect(queue.items, hasLength(2), reason: 'user + fallback reply');
        expect(queue.items.map((i) => i.data['sender']), ['user', 'ai']);
        queue.items.forEach(_expectLiveMessage);

        // Link (same uid) and claim (another uid) uploads.
        const anon = 'anon-secret';
        final anonSalt = KoiCryptoService().generateSalt();
        final linkStore = MemoryMessageStore();
        await linkStore.put(
          _record('L1', await cipher.encrypt('hello', anon, anonSalt)),
        );
        final uploader = _AckUploader();
        final m = CseMigration(
          messages: linkStore,
          checkIns: MemoryCheckInBox(),
          cipher: cipher,
          uploader: uploader,
          markers: MemoryKeyValueStore(),
        );
        await m.beginLink(_uid);
        await m.runLink(uid: _uid, fromSecret: anon, to: testCryptoContext);
        await m.offerClaim(source: _uid, target: 'u2');
        await m.runClaim(
          target: 'u2',
          fromSecret: testCryptoContext.secret,
          to: testCryptoContext,
        );
        expect(uploader.uploads.map((i) => i.docId), ['L1', 'L1_u2']);
        for (final item in uploader.uploads) {
          final d = firestoreData(item);
          expect(d.keys.toSet(), liveMessageKeys);
          expect(d['id'], item.docId);
          expect(d['conversationId'], item.collection.split('/')[3]);
          expect(liveRulesViolation(item), isNull);
        }
        _expectLiveMessage(uploader.uploads.first);
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );

    test('users/{uid} writes: only that document, any fields (rules)', () {
      final items = [
        SyncItem.saltCreateOnce(_uid, KoiCryptoService().generateSalt()),
        onboardingProfileItem(
          _uid,
          const OnboardingData(
            avatar: 'female_human',
            companion: 'aisha',
            language: 'en',
            notificationTime: '09:00',
            notificationsEnabled: true,
          ),
        ),
        settingsProfileItem(_uid, const SettingsPrefs(companion: 'raza')),
      ];
      for (final i in items) {
        expect(i.collection, 'users');
        expect(i.docId, _uid);
        expect(i.ownerUid, _uid);
        expect(liveRulesViolation(i), isNull);
      }
      // The create-once user document: plain fields + server timestamps.
      expect(newUserDocument(_uid)['koiUuid'], _uid);
    });
  });

  group('LIVE-02 the pre-check mirrors messageOk (never weaker)', () {
    test('a full valid record passes', () {
      expect(liveRulesViolation(_message(_valid()), now: _now), isNull);
    });

    final breaches = <String, (Map<String, Object?> Function(), String)>{
      'extra key': (() => {..._valid(), 'crisis_flag': false}, 'keys'),
      'missing key': (() => _valid()..remove('synced'), 'keys'),
      'id != mid': (() => {..._valid(), 'id': 'other'}, 'id'),
      'cid mismatch': (
        () => {..._valid(), 'conversationId': 'u9'},
        'conversationId',
      ),
      'sender not user/ai': (
        () => {..._valid(), 'sender': 'assistant'},
        'sender',
      ),
      'plaintext content': (() => {..._valid(), 'content': 'hello'}, 'content'),
      'url-safe base64': (
        () => {..._valid(), 'content': _ct.replaceFirst('AAAA:', 'AA-_:')},
        'content',
      ),
      'salt without ==': (
        () => {..._valid(), 'content': _ct.replaceFirst('AA==:', 'AAAA:')},
        'content',
      ),
      'over 64 KB': (
        () => {..._valid(), 'content': '$_ct${'A' * 65536}'},
        'content',
      ),
      'timestamp as int': (
        () => {..._valid(), 'timestamp': 1761037200000},
        'timestamp',
      ),
      'timestamp > now + 5 min': (
        () => {..._valid(), 'timestamp': '2026-10-20T09:06:01.000Z'},
        'timestamp',
      ),
      'emotion over 32': (() => {..._valid(), 'emotion': 'e' * 33}, 'emotion'),
      'confidence > 1': (
        () => {..._valid(), 'emotion_confidence': 1.5},
        'emotion_confidence',
      ),
      'confidence as string': (
        () => {..._valid(), 'emotion_confidence': '1'},
        'emotion_confidence',
      ),
      'synced as string': (() => {..._valid(), 'synced': 'false'}, 'synced'),
    };
    for (final MapEntry(key: name, value: (build, reason))
        in breaches.entries) {
      test(name, () {
        expect(liveRulesViolation(_message(build()), now: _now), reason);
      });
    }

    test('a timestamp stored as a string (not converted) is denied', () {
      final item = SyncItem(
        collection: ConversationService.messagesCollection(_uid, _uid),
        docId: 'm1',
        data: _valid(),
        priority: 3, // no timestampFields → stays a string
      );
      expect(liveRulesViolation(item, now: _now), 'timestamp');
    });

    test('every other path is denied (check-ins, mood, other collections)', () {
      for (final c in [
        'users/$_uid/checkins',
        'users/$_uid/mood',
        'conversations/$_uid/messages',
        'messages',
      ]) {
        final item = SyncItem(collection: c, docId: 'x', data: {}, priority: 2);
        expect(liveRulesViolation(item), 'path', reason: c);
      }
    });
  });

  group('LIVE-03 the real writer never sends a denied item', () {
    test(
      'pre-check failure → nothing in Firestore, dropped and counted',
      () async {
        final db = FakeFirebaseFirestore();
        final writer = FirestoreRemoteWriter(
          firestore: db,
          currentUid: () => _uid,
          userDocs: UserDocumentStore(db),
          saltCache: SaltCache(),
        );
        final q = PersistentSyncQueue(
          store: MemoryKeyValueStore(),
          remote: writer,
        );
        await q.enqueueAsync(_message({..._valid(), 'extra': 1}));
        await q.enqueueAsync(_message(_valid(), docId: 'm1'));
        final docs = await db
            .collection(ConversationService.messagesCollection(_uid, _uid))
            .get();
        expect(docs.docs.map((d) => d.id), [
          'm1',
        ], reason: 'only the valid one');
        expect(q.pending, isEmpty);
        expect(q.rejectedCounts, {'precheck-keys': 1});
      },
    );
  });

  group('LIVE-04 terminal codes, back-off, and retryable failures', () {
    test(
      'permission-denied / invalid-argument: dropped at once, counted',
      () async {
        final store = MemoryKeyValueStore();
        final remote = _Remote(
          (i) => _fb(i.docId == 'a' ? 'permission-denied' : 'invalid-argument'),
        );
        final q = PersistentSyncQueue(store: store, remote: remote);
        await q.enqueueAsync(_message(_valid(), docId: 'a'));
        await q.enqueueAsync(_message(_valid(), docId: 'b'));
        await q.flush();
        expect(q.pending, isEmpty);
        expect(remote.calls, 2, reason: 'each tried exactly once');
        expect(q.rejectedCounts, {
          'permission-denied': 1,
          'invalid-argument': 1,
        });
        expect(
          store.get(PersistentSyncQueue.rejectedKey),
          isNot(contains('PBKDF2')),
          reason: 'codes only, never data',
        );
      },
    );

    test(
      'failed-precondition: back-off, at most 5 attempts, then dropped',
      () async {
        var now = 0;
        final remote = _Remote((_) => _fb('failed-precondition'));
        final q = PersistentSyncQueue(
          store: MemoryKeyValueStore(),
          remote: remote,
          now: () => now,
        );
        await q.enqueueAsync(_message(_valid()));
        expect(q.pending.single.attempts, 1);
        expect(q.pending.single.retryAfter, 30000);
        await q.flush(); // before retryAfter: not tried
        expect(remote.calls, 1);
        for (var attempt = 2; attempt <= 4; attempt++) {
          now = q.pending.single.retryAfter!;
          await q.flush();
          expect(remote.calls, attempt);
          expect(q.pending.single.attempts, attempt);
          expect(
            q.pending.single.retryAfter,
            now + syncBackoff(attempt).inMilliseconds,
          );
        }
        now = q.pending.single.retryAfter!;
        await q.flush(); // 5th attempt
        expect(remote.calls, 5);
        expect(q.pending, isEmpty);
        expect(q.rejectedCounts, {'failed-precondition': 1});
      },
    );

    test('timeout / unavailable / network keep retrying as before', () async {
      final remote = _Remote(
        (i) => i.docId == 'a' ? _fb('unavailable') : StateError('network'),
      );
      final q = PersistentSyncQueue(
        store: MemoryKeyValueStore(),
        remote: remote,
      );
      await q.enqueueAsync(_message(_valid(), docId: 'a'));
      await q.enqueueAsync(_message(_valid(), docId: 'b'));
      for (var i = 0; i < 10; i++) {
        await q.flush();
      }
      expect(q.pending.map((i) => i.docId), ['a', 'b']);
      expect(q.pending.every((i) => i.attempts == 0), isTrue);
      expect(q.rejectedCounts, isEmpty);
    });

    test('attempts / retryAfter survive persistence; old JSON reads as 0', () {
      final item = _message(_valid()).backedOff(1000);
      final back = SyncItem.fromJson(
        (jsonDecode(jsonEncode(item.toJson())) as Map).cast(),
      );
      expect(back.attempts, 1);
      expect(back.retryAfter, 1000 + 30000);
      final old = SyncItem.fromJson({
        'collection': 'users',
        'docId': _uid,
        'data': <String, Object?>{},
        'priority': 4,
      });
      expect(old.attempts, 0);
      expect(old.retryAfter, isNull);
    });

    test(
      'writeNow: a terminal failure throws SyncRejected, never queued',
      () async {
        final q = PersistentSyncQueue(
          store: MemoryKeyValueStore(),
          remote: _Remote((_) => _fb('permission-denied')),
        );
        await expectLater(
          q.writeNow(_message(_valid())),
          throwsA(
            isA<SyncRejected>().having(
              (e) => e.code,
              'code',
              'permission-denied',
            ),
          ),
        );
        expect(q.pending, isEmpty);
      },
    );
  });

  group('LIVE-05 link migration: refused copies become serverStale', () {
    test('migration finishes; the refused id is never retried', () async {
      final cipher = FakeCipher();
      final messages = MemoryMessageStore();
      for (final id in ['m1', 'm2']) {
        await messages.put(_record(id, await cipher.encrypt(id, 'anon', 's')));
      }
      final uploader = _RejectingUploader({'m1'});
      final markers = MemoryKeyValueStore();
      final m = CseMigration(
        messages: messages,
        checkIns: MemoryCheckInBox(),
        cipher: _SecretAwareCipher(),
        uploader: uploader,
        markers: markers,
      );
      // Re-encrypt from FakeCipher payloads: use a cipher that knows both.
      await m.beginLink(_uid);
      final report = await m.runLink(
        uid: _uid,
        fromSecret: 'anon',
        to: const CryptoContext(secret: 'pw', saltB64: 'salt'),
      );
      expect(report.state, MigrationState.done);
      expect(report.serverStale, 1);
      expect(m.linkMarker(_uid)!.serverStale, {'m1'});
      expect(m.linkMarker(_uid)!.acked, {'m2'});
      // The local record of the refused message is kept (re-encrypted).
      expect((await messages.byConversation(_uid)).map((r) => r.id), [
        'm1',
        'm2',
      ]);

      // A re-run (e.g. resume) never sends m1 again.
      uploader.attempts.clear();
      await markers.put(
        CseMigration.linkKey(_uid),
        m
            .linkMarker(_uid)!
            .copyWith(state: MigrationState.awaitingAck)
            .encode(),
      );
      final again = await m.runLink(
        uid: _uid,
        fromSecret: 'anon',
        to: const CryptoContext(secret: 'pw', saltB64: 'salt'),
      );
      expect(uploader.attempts, isEmpty);
      expect(again.serverStale, 1);
      // The marker survives an encode/decode round trip.
      final decoded = MigrationMarker.decode(m.linkMarker(_uid)!.encode())!;
      expect(decoded.serverStale, {'m1'});
    });

    test(
      'the anonymous secret is KEPT while any copy is serverStale',
      () async {
        Future<String?> linkWith(Set<String> reject) async {
          final h = Mob1Harness(
            user: const KoiUser(uid: 'a1', isAnonymous: true),
          );
          final anon = await h.secrets.anonymousSecret('a1');
          await h.messages.put(
            MessageRecord(
              id: 'm1',
              conversationId: 'a1',
              sender: 'user',
              content: await h.cipher.encrypt('hello', anon, 's'),
              timestamp: DateTime.utc(2026, 10, 20, 8),
              emotion: Emotion.neutral,
              emotionConfidence: 1,
              synced: false,
            ),
          );
          final c = AccountController(
            auth: h.auth,
            secrets: h.secrets,
            migration: CseMigration(
              messages: h.messages,
              checkIns: h.checkIns,
              cipher: h.cipher,
              uploader: _RejectingUploader(reject),
              markers: h.prefs,
            ),
            resolveContext: (uid, {linkedSecret}) async =>
                CryptoContext(secret: linkedSecret ?? 'anon', saltB64: 'salt'),
            ensureSalt: (uid) async => 'salt',
            onboarding: OnboardingStore(h.prefs),
            messages: h.messages,
            cipher: h.cipher,
            prefs: h.prefs,
            cleanup: AccountCleanup(),
          );
          await c.upgradeAnonymous('a@x', 'pwA');
          expect(c.migrationPending, isFalse, reason: 'the app runs');
          return h.secrets.existingAnonymousSecret('a1');
        }

        expect(await linkWith({'m1'}), isNotNull, reason: 'serverStale');
        expect(await linkWith({}), isNull, reason: 'all acknowledged');
      },
    );
  });
}

/// `v1:S:{secret}:{plain}`: lets a test see which secret a payload uses.
class _SecretAwareCipher implements MessageCipher {
  final _fake = FakeCipher();
  @override
  Future<String> encrypt(
    String plaintext,
    String secret,
    String saltB64,
  ) async => 'v1:S:$secret:$plaintext';
  @override
  Future<String> decrypt(String payload, String secret) async {
    if (payload.startsWith('v1:S:$secret:')) {
      return payload.substring('v1:S:$secret:'.length);
    }
    if (payload.startsWith('v1:FAKE:') && secret == 'anon') {
      return _fake.decrypt(payload, secret);
    }
    throw const FormatException('wrong secret');
  }
}
