import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/account/account_controller.dart';
import 'package:koi_mobile/account/account_migration.dart';
import 'package:koi_mobile/account/secret_store.dart';
import 'package:koi_mobile/chat/message_record.dart';
import 'package:koi_mobile/checkins/checkin_store.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/core/crypto_context.dart';
import 'package:koi_mobile/core/emotion.dart';
import 'package:koi_mobile/core/key_value_store.dart';
import 'package:koi_mobile/core/onboarding_store.dart';
import 'package:koi_mobile/core/sync_queue.dart';

import '../support/mob1_fakes.dart';

/// Acknowledges writes unless told to fail; records every upload.
class _Uploader implements MigrationUploader {
  final uploads = <SyncItem>[];
  final queued = <SyncItem>[];
  bool fail = false;

  @override
  Future<bool> writeNow(SyncItem item) async {
    if (fail) {
      queued.add(item);
      return false;
    }
    uploads.add(item);
    return true;
  }

  @override
  Future<int> removeWhere(bool Function(SyncItem item) test) async {
    final before = queued.length;
    queued.removeWhere(test);
    return before - queued.length;
  }
}

MessageRecord _msg(String id, String uid, String content, int minute) =>
    MessageRecord(
      id: id,
      conversationId: uid,
      sender: 'user',
      content: content,
      timestamp: DateTime.utc(2026, 10, 19, 10, minute),
      emotion: Emotion.neutral,
      emotionConfidence: 1,
      synced: false,
    );

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('MOB1-12 per-uid secrets (flutter_lib unchanged)', () {
    test('the legacy device secret is copied ONCE, to the first uid', () async {
      final kv = MemorySecureKv({AccountSecretStore.legacyAnonKey: 'LEGACY'});
      final s = AccountSecretStore(kv);
      expect(await s.anonymousSecret('a1'), 'LEGACY');
      expect(await s.anonymousSecret('a1'), 'LEGACY');
      final other = await s.anonymousSecret('a2');
      expect(other, isNot('LEGACY'));
      expect(kv.values[AccountSecretStore.anonKey('a2')], other);
      expect(await s.existingAnonymousSecret('a3'), isNull);
    });
    test('concurrent first calls create ONE secret', () async {
      final s = AccountSecretStore(MemorySecureKv());
      final both = await Future.wait([
        s.anonymousSecret('x'),
        s.anonymousSecret('x'),
      ]);
      expect(both[0], both[1]);
    });
    test(
      'linked secret per uid; deleteAnonymousSecret also drops its legacy copy',
      () async {
        final kv = MemorySecureKv({AccountSecretStore.legacyAnonKey: 'L'});
        final s = AccountSecretStore(kv);
        await s.anonymousSecret('a1');
        await s.setLinkedSecret('a1', 'pw');
        expect(await s.linkedSecret('a1'), 'pw');
        expect(await s.linkedSecret('b1'), isNull);
        await s.deleteAnonymousSecret('a1');
        expect(
          kv.values.containsKey(AccountSecretStore.legacyAnonKey),
          isFalse,
        );
        await s.clearLinkedSecret('a1');
        expect(await s.linkedSecret('a1'), isNull);
      },
    );
  });

  group('MOB1-13 link: same uid, history re-encrypted with the password', () {
    test('messages + check-ins move to the new secret; acked; anon secret kept until done', () async {
      final cipher = SecretCipher();
      final messages = MemoryMessageStore();
      final checkIns = MemoryCheckInBox();
      final uploader = _Uploader();
      final prefs = MemoryKeyValueStore();
      const anon = 'ANON';
      const to = CryptoContext(secret: 'pw', saltB64: 'salt-a1');
      await messages.put(
        _msg('m1', 'a1', await cipher.encrypt('hi', anon, 's'), 1),
      );
      await messages.put(
        _msg('m2', 'a1', await cipher.encrypt('there', anon, 's'), 2),
      );
      await checkIns.put(
        'a1_2026-10-19_morning',
        jsonEncode({
          'id': 'a1_2026-10-19_morning',
          'userId': 'a1',
          'kind': 'morning',
          'day': '2026-10-19',
          'timestamp': '2026-10-19T09:00:00.000',
          'synced': false,
          'payload': await cipher.encrypt('{"mood":3}', anon, 's'),
        }),
      );
      final m = CseMigration(
        messages: messages,
        checkIns: checkIns,
        cipher: cipher,
        uploader: uploader,
        markers: prefs,
      );
      await m.beginLink('a1');
      final report = await m.runLink(uid: 'a1', fromSecret: anon, to: to);
      expect(report.state, MigrationState.done);
      expect(report.reencrypted, 3);
      for (final r in await messages.byConversation('a1')) {
        expect(SecretCipher.secretOf(r.content), 'pw');
      }
      expect(
        await cipher.decrypt(
          (await messages.byConversation('a1')).first.content,
          'pw',
        ),
        'hi',
      );
      final row = jsonDecode(checkIns.rows.values.single) as Map;
      expect(SecretCipher.secretOf(row['payload'] as String), 'pw');
      expect(uploader.uploads.map((i) => i.docId), ['m1', 'm2']);
      expect(
        uploader.uploads.every((i) => !jsonEncode(i.data).contains('hi"')),
        isTrue,
        reason: 'only ciphertext is uploaded',
      );
    });
  });

  group('MOB1-14 interrupted link migration resumes without duplicates', () {
    test('no ack → awaitingAck; old-ciphertext queue items dropped; rerun uploads only the rest', () async {
      final cipher = SecretCipher();
      final messages = MemoryMessageStore();
      final uploader = _Uploader()..fail = true;
      final prefs = MemoryKeyValueStore();
      const to = CryptoContext(secret: 'pw', saltB64: 's');
      await messages.put(
        _msg('m1', 'a1', await cipher.encrypt('one', 'ANON', 's'), 1),
      );
      await messages.put(
        _msg('m2', 'a1', await cipher.encrypt('two', 'ANON', 's'), 2),
      );
      // An old-ciphertext write still queued from the anonymous phase.
      uploader.queued.add(
        SyncItem(
          collection: 'users/a1/conversations/a1/messages',
          docId: 'm1',
          data: const {'content': 'OLD'},
          priority: 3,
        ),
      );
      final m = CseMigration(
        messages: messages,
        checkIns: MemoryCheckInBox(),
        cipher: cipher,
        uploader: uploader,
        markers: prefs,
      );
      final first = await m.runLink(uid: 'a1', fromSecret: 'ANON', to: to);
      expect(first.state, MigrationState.awaitingAck);
      expect(uploader.queued.where((i) => i.data['content'] == 'OLD'), isEmpty);
      final encryptsAfterFirst = cipher.encrypts;

      uploader.fail = false;
      uploader.queued.clear();
      final second = await m.runLink(uid: 'a1', fromSecret: 'ANON', to: to);
      expect(second.state, MigrationState.done);
      expect(second.reencrypted, 0, reason: 'already re-encrypted');
      expect(second.alreadyDone, 2);
      expect(
        cipher.encrypts,
        encryptsAfterFirst,
        reason: 'nothing encrypted twice',
      );
      expect(uploader.uploads.map((i) => i.docId), ['m1', 'm2']);

      // A third run is a no-op: no duplicate uploads.
      await m.runLink(uid: 'a1', fromSecret: 'ANON', to: to);
      expect(uploader.uploads, hasLength(2));
    });
  });

  group('MOB1-15 claim: copies kept until the server acknowledges', () {
    test('source rows stay while unacked; deleted only after every ack; rerun = no duplicates', () async {
      final cipher = SecretCipher();
      final messages = MemoryMessageStore();
      final uploader = _Uploader()..fail = true;
      final prefs = MemoryKeyValueStore();
      const to = CryptoContext(secret: 'pwB', saltB64: 'salt-b1');
      await messages.put(
        _msg('m1', 'a1', await cipher.encrypt('one', 'ANON', 's'), 1),
      );
      await messages.put(
        _msg('m2', 'a1', await cipher.encrypt('two', 'ANON', 's'), 2),
      );
      final m = CseMigration(
        messages: messages,
        checkIns: MemoryCheckInBox(),
        cipher: cipher,
        uploader: uploader,
        markers: prefs,
      );
      await m.offerClaim(source: 'a1', target: 'b1');
      final r1 = await m.runClaim(target: 'b1', fromSecret: 'ANON', to: to);
      expect(r1.state, MigrationState.awaitingAck);
      expect(
        await messages.byConversation('a1'),
        hasLength(2),
        reason: 'kept until ack',
      );
      final copies = await messages.byConversation('b1');
      expect(copies.map((r) => r.id), [
        'm1_b1',
        'm2_b1',
      ], reason: 'stable derived ids');
      expect(
        copies.every((r) => SecretCipher.secretOf(r.content) == 'pwB'),
        isTrue,
      );

      uploader.fail = false;
      final r2 = await m.runClaim(target: 'b1', fromSecret: 'ANON', to: to);
      expect(r2.state, MigrationState.done);
      expect(await messages.byConversation('a1'), isEmpty);
      expect(
        await messages.byConversation('b1'),
        hasLength(2),
        reason: 'no duplicates',
      );
      expect(uploader.uploads.map((i) => i.collection).toSet(), {
        'users/b1/conversations/b1/messages',
      });
      expect(uploader.uploads, hasLength(2));
    });
  });

  AccountController controller(Mob1Harness h) => AccountController(
    auth: h.auth,
    secrets: h.secrets,
    migration: CseMigration(
      messages: h.messages,
      checkIns: h.checkIns,
      cipher: h.cipher,
      uploader: _Uploader(),
      markers: h.prefs,
    ),
    resolveContext: (uid, {linkedSecret}) async =>
        CryptoContext(secret: linkedSecret ?? 'anon', saltB64: 'salt-$uid'),
    ensureSalt: (uid) async => 'salt-$uid',
    onboarding: OnboardingStore(h.prefs),
    messages: h.messages,
    cipher: h.cipher,
    prefs: h.prefs,
    cleanup: AccountCleanup(),
  );

  group(
    'MOB1-16 another account never silently gets this device\'s history',
    () {
      test('sign-in from anonymous only OFFERS a claim; "Leave it" keeps the rows hidden', () async {
        final h = Mob1Harness(
          user: const KoiUser(uid: 'a1', isAnonymous: true),
        );
        h.auth.accounts['b@x'] = ('b1', 'pwB');
        final anon = await h.secrets.anonymousSecret('a1');
        await h.messages.put(
          _msg('m1', 'a1', await h.cipher.encrypt('mine', anon, 's'), 1),
        );
        final c = controller(h);
        await c.signInExisting('b@x', 'pwB');
        expect(h.auth.user!.uid, 'b1');
        expect(await h.messages.byConversation('b1'), isEmpty);
        expect(c.claimOffered, isTrue);
        await c.leaveClaim();
        expect(c.claimOffered, isFalse);
        expect(await h.messages.byConversation('a1'), hasLength(1));
        expect(await h.messages.byConversation('b1'), isEmpty);
      });
      test('no anonymous history → no claim offered', () async {
        final h = Mob1Harness(
          user: const KoiUser(uid: 'a1', isAnonymous: true),
        );
        h.auth.accounts['b@x'] = ('b1', 'pwB');
        final c = controller(h);
        await c.signInExisting('b@x', 'pwB');
        expect(c.claimOffered, isFalse);
      });
    },
  );

  group(
    'MOB1-17 accepting a claim requires re-authentication of the target',
    () {
      test('wrong password → nothing copied; right password → copied + onboarding kept', () async {
        final h = Mob1Harness(
          user: const KoiUser(uid: 'a1', isAnonymous: true),
          onboarded: false,
        );
        await h.onboarding.markComplete('a1');
        h.auth.accounts['b@x'] = ('b1', 'pwB');
        final anon = await h.secrets.anonymousSecret('a1');
        await h.messages.put(
          _msg('m1', 'a1', await h.cipher.encrypt('mine', anon, 's'), 1),
        );
        final c = controller(h);
        await c.signInExisting('b@x', 'pwB');
        await expectLater(
          c.acceptClaim('nope'),
          throwsA(isA<AccountAuthException>()),
        );
        expect(await h.messages.byConversation('b1'), isEmpty);
        await c.acceptClaim('pwB');
        final copies = await h.messages.byConversation('b1');
        expect(copies, hasLength(1));
        expect(await h.cipher.decrypt(copies.single.content, 'pwB'), 'mine');
        expect(h.onboarding.isCompleteFor('b1'), isTrue);
        expect(h.auth.reauthCalls, 2);
      });
    },
  );

  group('MOB1-18 upgrade: same uid; collision handled', () {
    test('link keeps the uid, caches the password and re-encrypts', () async {
      final h = Mob1Harness(user: const KoiUser(uid: 'a1', isAnonymous: true));
      final anon = await h.secrets.anonymousSecret('a1');
      await h.messages.put(
        _msg('m1', 'a1', await h.cipher.encrypt('hello', anon, 's'), 1),
      );
      final c = controller(h);
      await c.upgradeAnonymous('a@x', 'pwA');
      expect(h.auth.user!.uid, 'a1');
      expect(h.auth.isLinked, isTrue);
      expect(await h.secrets.linkedSecret('a1'), 'pwA');
      final row = (await h.messages.byConversation('a1')).single;
      expect(SecretCipher.secretOf(row.content), 'pwA');
      expect(c.unlock, UnlockState.notNeeded);
      expect(c.migrationPending, isFalse);
      expect(
        await h.secrets.existingAnonymousSecret('a1'),
        isNull,
        reason: 'all copies acknowledged → anonymous secret removed',
      );
    });
    test(
      'credential collision → error, marker removed, still anonymous',
      () async {
        final h = Mob1Harness(
          user: const KoiUser(uid: 'a1', isAnonymous: true),
        );
        h.auth.accounts['taken@x'] = ('zz', 'pw');
        final c = controller(h);
        await expectLater(
          c.upgradeAnonymous('taken@x', 'pw2'),
          throwsA(
            isA<AccountAuthException>().having(
              (e) => e.error,
              'error',
              AccountAuthError.emailInUse,
            ),
          ),
        );
        expect(h.auth.user!.isAnonymous, isTrue);
        expect(h.prefs.get(CseMigration.linkKey('a1')), isNull);
        expect(await h.secrets.linkedSecret('a1'), isNull);
      },
    );
    test(
      'a crash after linking resumes the migration on the next start',
      () async {
        final h = Mob1Harness(user: AccountFakeAuth.registered('a1', 'a@x'));
        final anon = await h.secrets.anonymousSecret('a1');
        await h.messages.put(
          _msg('m1', 'a1', await h.cipher.encrypt('x', anon, 's'), 1),
        );
        await h.secrets.setLinkedSecret('a1', 'pwA');
        await h.prefs.put(
          CseMigration.linkKey('a1'),
          const MigrationMarker(state: MigrationState.pending).encode(),
        );
        final c = controller(h);
        await pumpEventQueue();
        expect(c.migrationPending, isFalse);
        expect(
          SecretCipher.secretOf(
            (await h.messages.byConversation('a1')).single.content,
          ),
          'pwA',
        );
      },
    );
  });

  group('MOB1-20 unlock on a new device', () {
    test(
      'linked user without a cached password needs unlock; reauth fixes it',
      () async {
        final h = Mob1Harness(user: AccountFakeAuth.registered('b1', 'b@x'));
        h.auth.accounts['b@x'] = ('b1', 'pwB');
        final c = controller(h);
        await pumpEventQueue();
        expect(c.unlock, UnlockState.needed);
        await expectLater(
          c.unlockWith('bad'),
          throwsA(isA<AccountAuthException>()),
        );
        expect(c.unlock, UnlockState.needed);
        await c.unlockWith('pwB');
        expect(c.unlock, UnlockState.notNeeded);
        expect(await h.secrets.linkedSecret('b1'), 'pwB');
      },
    );
  });

  group('MOB1-19 sign-out clears the account\'s secret and stores', () {
    test('linked secret gone, cleanup ran for that uid', () async {
      final h = Mob1Harness(user: AccountFakeAuth.registered('b1', 'b@x'));
      await h.secrets.setLinkedSecret('b1', 'pwB');
      final c = controller(h);
      final cleaned = <String>[];
      c.cleanup.onSignOut((uid) async => cleaned.add('signOut:$uid'));
      c.cleanup.onLeave((uid) async => cleaned.add('leave:$uid'));
      await c.signOut();
      expect(h.auth.user, isNull);
      expect(await h.secrets.linkedSecret('b1'), isNull);
      expect(cleaned, containsAll(['signOut:b1', 'leave:b1']));
    });
  });

  group('MOB1-39 sync queue: acknowledged writes and dropping stale items', () {
    test(
      'writeNow true only when written; removeWhere drops matches',
      () async {
        final store = MemoryKeyValueStore();
        final remote = _OkRemote();
        final q = PersistentSyncQueue(store: store, remote: remote);
        final item = SyncItem(
          collection: 'users/u1/x',
          docId: 'd',
          data: const {},
          priority: 3,
        );
        expect(await q.writeNow(item), isTrue);
        remote.fail = true;
        expect(await q.writeNow(item), isFalse);
        expect(q.pending, hasLength(1));
        expect(await q.removeWhere((i) => i.docId == 'd'), 1);
        expect(q.pending, isEmpty);
      },
    );
  });
}

class _OkRemote implements RemoteWriter {
  bool fail = false;
  @override
  bool get isReady => true;
  @override
  bool owns(SyncItem item) => true;
  @override
  Future<void> write(SyncItem item) async {
    if (fail) throw StateError('down');
  }
}
