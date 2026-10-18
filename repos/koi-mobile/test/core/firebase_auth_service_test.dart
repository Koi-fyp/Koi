import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/core/auth/firebase_auth_service.dart';
import 'package:koi_mobile/core/firebase/firebase_config.dart';
import 'package:koi_mobile/core/firebase/firebase_session.dart';
import 'package:koi_mobile/landing/landing_screen.dart';

/// Hand-written stand-in for firebase_auth.
class _FakeBackend implements AuthBackend {
  final changes = StreamController<KoiUser?>.broadcast();
  Object? signInError;
  String? token;
  int signOuts = 0;

  @override
  Stream<KoiUser?> get userChanges => changes.stream;

  @override
  Future<KoiUser> signInAnonymously() async {
    if (signInError != null) throw signInError!;
    const u = KoiUser(uid: 'fb-1', isAnonymous: true);
    changes.add(u);
    return u;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    changes.add(null);
  }

  @override
  Future<String> getIdToken() async =>
      token ?? (throw StateError('No authenticated Firebase user'));
}

void main() {
  group('ATC-M1-03 FirebaseAuthService', () {
    test('loading until the first auth event restores the session', () async {
      final b = _FakeBackend();
      final s = FirebaseAuthService(b);
      expect(s.loading, isTrue);
      expect(s.sessionRestored, isFalse);

      b.changes.add(const KoiUser(uid: 'restored', isAnonymous: true));
      await pumpEventQueue();
      expect(s.sessionRestored, isTrue);
      expect(s.loading, isFalse);
      expect(s.user?.uid, 'restored');
      expect(s.isAnonymous, isTrue);
      s.dispose();
    });

    test('no persisted user → restored with user null', () async {
      final b = _FakeBackend();
      final s = FirebaseAuthService(b);
      b.changes.add(null);
      await pumpEventQueue();
      expect(s.sessionRestored, isTrue);
      expect(s.user, isNull);
      s.dispose();
    });

    test('signInAnonymously sets the user; signOut clears it', () async {
      final b = _FakeBackend();
      final s = FirebaseAuthService(b);
      b.changes.add(null);
      await pumpEventQueue();

      await s.signInAnonymously();
      expect(s.user?.uid, 'fb-1');
      expect(s.error, isNull);
      expect(s.loading, isFalse);

      await s.signOut();
      expect(s.user, isNull);
      expect(b.signOuts, 1);
      s.dispose();
    });

    test('anonymous sign-in disabled → clear error, no throw, landing text', () async {
      final b = _FakeBackend()
        ..signInError = const AnonymousSignInDisabledError(
          'operation-not-allowed',
        );
      final s = FirebaseAuthService(b);
      b.changes.add(null);
      await pumpEventQueue();

      await s.signInAnonymously();
      expect(s.user, isNull);
      expect(s.loading, isFalse);
      expect(s.error, isA<AnonymousSignInDisabledError>());
      expect(
        LandingScreen.errorTextFor(s.error),
        'Sign-in is turned off for this app right now. Please try again later.',
      );
      expect(
        LandingScreen.errorTextFor(StateError('network')),
        LandingScreen.errorText,
      );
      s.dispose();
    });

    test('getIdToken comes from the backend; throws with no user', () async {
      final b = _FakeBackend();
      final s = FirebaseAuthService(b);
      await expectLater(s.getIdToken(), throwsStateError);
      b.token = 'tok';
      expect(await s.getIdToken(), 'tok');
      s.dispose();
    });

    test('anonymous-disabled codes', () {
      expect(anonymousDisabledCodes, contains('operation-not-allowed'));
      expect(anonymousDisabledCodes, contains('admin-restricted-operation'));
    });
  });

  group('ATC-M1-04 FirebaseConfig.fromValues', () {
    test('nothing set → null (debug stand-in)', () {
      expect(
        FirebaseConfig.fromValues(
          apiKey: '',
          appId: '',
          messagingSenderId: '',
          projectId: '',
        ),
        isNull,
      );
    });

    test('all required set → options; empty bucket → null', () {
      final o = FirebaseConfig.fromValues(
        apiKey: 'k',
        appId: 'a',
        messagingSenderId: 's',
        projectId: 'p',
      )!;
      expect(o.projectId, 'p');
      expect(o.storageBucket, isNull);
    });

    test('partial → StateError naming keys, never values', () {
      expect(
        () => FirebaseConfig.fromValues(
          apiKey: 'secret-value',
          appId: '',
          messagingSenderId: 's',
          projectId: '',
        ),
        throwsA(
          isA<StateError>()
              .having(
                (e) => e.message,
                'message',
                contains('KOI_FIREBASE_APP_ID'),
              )
              .having((e) => e.message, 'message', contains('PROJECT_ID'))
              .having(
                (e) => e.message,
                'message',
                isNot(contains('secret-value')),
              ),
        ),
      );
    });

    test('this test run has no Firebase dart-defines', () {
      expect(FirebaseConfig.fromEnvironment(), isNull);
    });
  });

  group('ATC-M14-16 FirebaseSessionSync', () {
    late List<String> calls;
    late bool online;
    late bool userDocFails;
    late StreamController<bool> onlineChanges;
    late FirebaseSessionSync sync;

    setUp(() {
      calls = [];
      online = true;
      userDocFails = false;
      onlineChanges = StreamController<bool>();
      sync = FirebaseSessionSync(
        ensureUserDocument: (uid) async {
          calls.add('doc:$uid');
          if (userDocFails) throw StateError('offline');
        },
        ensureSalt: (uid) async => calls.add('salt:$uid'),
        isOnline: () async => online,
        flush: () async => calls.add('flush'),
        onlineChanges: onlineChanges.stream,
      );
    });

    tearDown(() => sync.dispose());

    test(
      'sign-in while online: user doc, then salt, then flush; once',
      () async {
        sync.userChanged('u1');
        await sync.runNow();
        expect(calls, ['doc:u1', 'salt:u1', 'flush']);

        sync.userChanged('u1'); // same uid again: nothing
        await sync.runNow();
        expect(calls, hasLength(3));
      },
    );

    test('offline: nothing until the device comes back online', () async {
      online = false;
      sync.userChanged('u1');
      await sync.runNow();
      expect(calls, isEmpty);

      online = true;
      onlineChanges.add(true);
      await pumpEventQueue();
      expect(calls, ['doc:u1', 'salt:u1', 'flush']);
    });

    test(
      'user doc fails → salt and flush still run; retried on reconnect',
      () async {
        userDocFails = true;
        sync.userChanged('u1');
        await sync.runNow();
        expect(calls, ['doc:u1', 'salt:u1', 'flush']);

        userDocFails = false;
        onlineChanges.add(true);
        await pumpEventQueue();
        expect(calls, hasLength(6));

        onlineChanges.add(true); // done now: no more runs
        await pumpEventQueue();
        expect(calls, hasLength(6));
      },
    );

    test('signed out → nothing; new uid runs for the new uid', () async {
      sync.userChanged(null);
      await sync.runNow();
      expect(calls, isEmpty);
      sync.userChanged('u2');
      await sync.runNow();
      expect(calls, ['doc:u2', 'salt:u2', 'flush']);
    });

    test('uid changes during a run → runs again for the new uid', () async {
      sync.userChanged('u1');
      sync.userChanged('u2');
      await pumpEventQueue();
      expect(calls, containsAllInOrder(['doc:u1', 'doc:u2']));
    });
  });
}
