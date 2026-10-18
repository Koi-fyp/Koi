import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/core/auth/debug_local_auth_service.dart';
import 'package:koi_mobile/core/key_value_store.dart';

import '../support/fake_auth.dart';

void main() {
  group('ATC-M1-01 isAnonymous / isLinked derivation (AuthContext.tsx)', () {
    bool anon(KoiUser? u) => FakeAuthService(fakeUser: u).isAnonymous;
    bool linked(KoiUser? u) => FakeAuthService(fakeUser: u).isLinked;

    test('no user: neither', () {
      expect(anon(null), isFalse);
      expect(linked(null), isFalse);
    });
    test('anonymous user: anonymous, not linked (even with password)', () {
      const u = KoiUser(uid: 'a', isAnonymous: true, providerIds: ['password']);
      expect(anon(u), isTrue);
      expect(linked(u), isFalse);
    });
    test('non-anonymous with password provider: linked', () {
      const u = KoiUser(
        uid: 'a',
        isAnonymous: false,
        providerIds: ['google.com', 'password'],
      );
      expect(anon(u), isFalse);
      expect(linked(u), isTrue);
    });
    test('non-anonymous without password provider: not linked', () {
      const u = KoiUser(
        uid: 'a',
        isAnonymous: false,
        providerIds: ['google.com'],
      );
      expect(linked(u), isFalse);
    });
  });

  group('ATC-M1-02 DebugLocalAuthService (temporary stand-in)', () {
    test(
      'loading until the session is restored; no stored uid → signed out',
      () async {
        final s = DebugLocalAuthService(() async => MemoryKeyValueStore());
        expect(s.loading, isTrue);
        expect(s.user, isNull);
        await s.restoreSession();
        expect(s.loading, isFalse);
        expect(s.user, isNull);
      },
    );

    test('restores a persisted uid as an anonymous user', () async {
      final store = MemoryKeyValueStore({
        DebugLocalAuthService.uidKey: 'debug-abc',
      });
      final s = DebugLocalAuthService(() async => store);
      await s.restoreSession();
      expect(s.user!.uid, 'debug-abc');
      expect(s.isAnonymous, isTrue);
      expect(s.isLinked, isFalse);
    });

    test('signIn persists a debug- uid, signOut removes it', () async {
      final store = MemoryKeyValueStore();
      final s = DebugLocalAuthService(() async => store);
      await s.restoreSession();

      final loadingSeen = <bool>[];
      s.addListener(() => loadingSeen.add(s.loading));
      await s.signInAnonymously();
      expect(loadingSeen, [true, false]);
      expect(s.user!.uid, startsWith('debug-'));
      expect(s.user!.uid, hasLength('debug-'.length + 32));
      expect(store.values[DebugLocalAuthService.uidKey], s.user!.uid);

      await s.signOut();
      expect(s.user, isNull);
      expect(store.values, isEmpty);
    });

    test('failures land in error (never thrown) and loading ends', () async {
      final s = DebugLocalAuthService(
        () async => throw StateError('disk full'),
      );
      await s.restoreSession();
      expect(s.loading, isFalse);
      expect(s.error, isA<StateError>());

      await s.signInAnonymously(); // must not throw
      expect(s.loading, isFalse);
      expect(s.user, isNull);
      expect(s.error, isA<StateError>());
    });
  });
}
