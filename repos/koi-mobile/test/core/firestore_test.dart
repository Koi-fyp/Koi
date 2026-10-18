import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/chat/conversation_service.dart';
import 'package:koi_mobile/core/crypto_context.dart';
import 'package:koi_mobile/core/firestore/firestore_remote_writer.dart';
import 'package:koi_mobile/core/firestore/profile_sync.dart';
import 'package:koi_mobile/core/firestore/user_document_store.dart';
import 'package:koi_mobile/core/sync_queue.dart';
import 'package:koi_mobile/onboarding/onboarding_service.dart';
import 'package:koi_mobile/settings/settings_prefs.dart';

const _uid = 'fb-uid-1';

class _Queue implements SyncQueue {
  final items = <SyncItem>[];
  @override
  void enqueue(SyncItem item) => items.add(item);
}

void main() {
  late FakeFirebaseFirestore db;
  late UserDocumentStore store;
  DocumentReference<Map<String, dynamic>> userDoc() =>
      db.collection('users').doc(_uid);

  setUp(() {
    db = FakeFirebaseFirestore();
    store = UserDocumentStore(db);
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('ensureCreated (users/{uid} create-once)', () {
    test('missing → web fields, koiUuid = uid, classification {}', () async {
      await store.ensureCreated(_uid);
      final data = (await userDoc().get()).data()!;
      expect(data.keys.toSet(), {
        'koiUuid',
        'createdAt',
        'lastActive',
        'profile',
        'classification',
        'settings',
        'stats',
      });
      expect(data['koiUuid'], _uid);
      expect(data['createdAt'], isA<Timestamp>());
      expect(data['lastActive'], isA<Timestamp>());
      expect(data['profile'], {
        'avatar': null,
        'language': 'en',
        'notificationTime': null,
      });
      expect(data['classification'], <String, Object?>{});
      expect(data['settings'], {
        'notifications_enabled': true,
        'sound_enabled': true,
        'haptic_enabled': true,
      });
      expect(data['stats'], {
        'total_conversations': 0,
        'total_check_ins': 0,
        'current_streak': 0,
        'longest_streak': 0,
        'jigsaw_pieces': 0,
      });
    });

    test('exists → nothing is overwritten', () async {
      await store.ensureCreated(_uid);
      await userDoc().set({
        'profile': {'language': 'ur'},
        'koiUuid': 'kept',
      }, SetOptions(merge: true));
      final before = (await userDoc().get()).data();
      await store.ensureCreated(_uid);
      expect((await userDoc().get()).data(), before);
    });

    test('partial doc → only missing top-level keys are added', () async {
      await userDoc().set({
        'profile': {'avatar': 'female_human', 'companion': 'aisha'},
        'onboarding_complete': true,
        'public_crypto_metadata': {'salt': 'S'},
      });
      await store.ensureCreated(_uid);
      final data = (await userDoc().get()).data()!;
      expect(data['profile'], {'avatar': 'female_human', 'companion': 'aisha'});
      expect(data['onboarding_complete'], true);
      expect(data['public_crypto_metadata'], {'salt': 'S'});
      expect(data['koiUuid'], _uid);
      expect(data['stats'], isA<Map<String, dynamic>>());
      expect(data['settings'], isA<Map<String, dynamic>>());
      expect(data['classification'], <String, Object?>{});
    });
  });

  group('createSaltOnce', () {
    test('missing (no doc) → ours stored and returned', () async {
      expect(await store.createSaltOnce(_uid, 'ours'), 'ours');
      expect((await userDoc().get()).data(), {
        'public_crypto_metadata': {'salt': 'ours'},
      });
    });

    test('doc without salt → ours merged in, other fields kept', () async {
      await store.ensureCreated(_uid);
      expect(await store.createSaltOnce(_uid, 'ours'), 'ours');
      final data = (await userDoc().get()).data()!;
      expect(data['public_crypto_metadata'], {'salt': 'ours'});
      expect(data['koiUuid'], _uid);
    });

    test(
      'remote salt exists and differs → returned, never overwritten',
      () async {
        await userDoc().set({
          'public_crypto_metadata': {'salt': 'remote'},
        });
        expect(await store.createSaltOnce(_uid, 'ours'), 'remote');
        expect(saltFromUserData((await userDoc().get()).data()), 'remote');
      },
    );

    test('empty remote salt counts as missing', () async {
      await userDoc().set({
        'public_crypto_metadata': {'salt': ''},
      });
      expect(await store.createSaltOnce(_uid, 'ours'), 'ours');
    });

    test('resolver end to end: first encrypt stores the salt once', () async {
      final resolver = CryptoContextResolver(
        fetchSalt: store.fetchSalt,
        createSaltOnce: store.createSaltOnce,
        isOnline: () async => true,
        syncQueue: _Queue(),
      );
      const anon = AuthState(isLinked: false);
      final ctx = await resolver.getActiveCryptoContext(_uid, anon);
      expect(saltFromUserData((await userDoc().get()).data()), ctx.saltB64);

      // Another device's cache is empty: it gets the same salt back.
      FlutterSecureStorage.setMockInitialValues({});
      final again = await resolver.getActiveCryptoContext(_uid, anon);
      expect(again.saltB64, ctx.saltB64);
    });
  });

  group('FirestoreRemoteWriter', () {
    late int keyClears;
    late String? signedIn;
    late FirestoreRemoteWriter writer;

    setUp(() {
      keyClears = 0;
      signedIn = _uid;
      writer = FirestoreRemoteWriter(
        firestore: db,
        currentUid: () => signedIn,
        userDocs: store,
        saltCache: SaltCache(onReplaced: () => keyClears++),
      );
    });

    test('ready and owns only for the signed-in uid', () {
      expect(writer.isReady, isTrue);
      expect(writer.owns(SyncItem.saltCreateOnce(_uid, 's')), isTrue);
      expect(writer.owns(SyncItem.saltCreateOnce('debug-x', 's')), isFalse);
      signedIn = null;
      expect(writer.isReady, isFalse);
      expect(writer.owns(SyncItem.saltCreateOnce(_uid, 's')), isFalse);
    });

    test(
      'message: nested path, Timestamp, content stays the v1 payload',
      () async {
        final when = DateTime.utc(2026, 10, 17, 9, 30);
        await writer.write(
          SyncItem(
            collection: ConversationService.messagesCollection(_uid, _uid),
            docId: 'm1',
            data: {
              'id': 'm1',
              'content': 'v1:PBKDF2:c2FsdA==:bm9uY2U=:Y3Q=',
              'timestamp': when.toIso8601String(),
            },
            priority: 3,
            timestampFields: const ['timestamp'],
          ),
        );
        final snap = await db
            .collection('users')
            .doc(_uid)
            .collection('conversations')
            .doc(_uid)
            .collection('messages')
            .doc('m1')
            .get();
        expect(snap.data()!['timestamp'], Timestamp.fromDate(when));
        expect(snap.data()!['content'], startsWith('v1:PBKDF2:'));
      },
    );

    test('queued salt create-once, remote differs → cache adopts remote, '
        'session keys cleared, Firestore unchanged', () async {
      await userDoc().set({
        'public_crypto_metadata': {'salt': 'remote'},
      });
      final cache = SaltCache();
      await cache.write(_uid, 'local');
      await writer.write(SyncItem.saltCreateOnce(_uid, 'local'));
      expect(await cache.read(_uid), 'remote');
      expect(keyClears, 1);
      expect(saltFromUserData((await userDoc().get()).data()), 'remote');
    });

    test(
      'queued salt create-once, missing → ours stored, cache kept',
      () async {
        final cache = SaltCache();
        await cache.write(_uid, 'local');
        await writer.write(SyncItem.saltCreateOnce(_uid, 'local'));
        expect(saltFromUserData((await userDoc().get()).data()), 'local');
        expect(await cache.read(_uid), 'local');
        expect(keyClears, 0);
      },
    );

    test(
      'onboarding then Settings merge into profile; name never written',
      () async {
        await store.ensureCreated(_uid);
        await writer.write(
          onboardingProfileItem(
            _uid,
            const OnboardingData(
              avatar: 'male_human',
              companion: 'koi',
              language: 'en',
              notificationTime: '20:00',
              notificationsEnabled: true,
            ),
          ),
        );
        await writer.write(
          settingsProfileItem(
            _uid,
            const SettingsPrefs(
              companion: 'aisha',
              name: 'Private Name',
              language: 'ur',
              notificationsEnabled: false,
              storedAvatar: 'male_human', // ignored: avatar follows companion
            ),
          ),
        );
        final data = (await userDoc().get()).data()!;
        expect(data['profile'], {
          'avatar': 'female_human',
          'companion': 'aisha',
          'language': 'ur',
          'notificationTime': '20:00',
        });
        expect(data['onboarding_complete'], true);
        expect(data['settings'], {
          'notifications_enabled': false,
          'sound_enabled': true,
          'haptic_enabled': true,
        });
        expect(data.toString(), isNot(contains('Private Name')));
      },
    );
  });

  test(
    'SyncingSettingsPrefsStore saves locally, then queues the merge',
    () async {
      final local = MemorySettingsPrefsStore();
      final queue = _Queue();
      final s = SyncingSettingsPrefsStore(local, queue);
      const prefs = SettingsPrefs(companion: 'raza', name: 'N');
      await s.save(_uid, prefs);
      expect(local.values[_uid], prefs);
      final item = queue.items.single;
      expect(item.collection, 'users');
      expect(item.docId, _uid);
      expect(item.priority, 4);
      expect(item.data.toString(), isNot(contains('name')));
      expect((item.data['profile'] as Map)['avatar'], 'male_human');
      expect(await s.load(_uid), prefs);
    },
  );

  test('settingsProfileItem: profile.avatar always matches companion', () {
    String avatarFor(String companion) =>
        (settingsProfileItem(
                  _uid,
                  SettingsPrefs(companion: companion, storedAvatar: 'x'),
                ).data['profile']
                as Map)['avatar']
            as String;
    expect(avatarFor('aisha'), 'female_human');
    expect(avatarFor('raza'), 'male_human');
    expect(avatarFor('koi'), 'fox');
  });
}
