import 'dart:async';

import 'package:flutter/foundation.dart';

import '../sync_queue.dart';

/// What runs once a Firebase user is signed in (new sign-in or restored
/// session), while online:
/// 1. users/{uid} create-once (UserDocumentStore.ensureCreated),
/// 2. salt create-once (CryptoContextResolver.ensureSaltStored), so the salt
///    is in Firestore before the first message,
/// 3. a sync-queue flush.
///
/// Offline, or if step 1 fails, it runs again when the device comes back
/// online. Never throws; logs only error codes.
class FirebaseSessionSync {
  FirebaseSessionSync({
    required this.ensureUserDocument,
    required this.ensureSalt,
    required this.isOnline,
    required this.flush,
    Stream<bool>? onlineChanges,
  }) {
    _sub = onlineChanges?.where((online) => online).listen((_) => _start());
  }

  final Future<void> Function(String uid) ensureUserDocument;

  /// Must not throw (ensureSaltStored doesn't).
  final Future<void> Function(String uid) ensureSalt;
  final Future<bool> Function() isOnline;
  final Future<void> Function() flush;

  StreamSubscription<bool>? _sub;
  String? _uid;
  final Set<String> _done = {};
  Future<void>? _running;

  /// Call with the signed-in uid on every auth change (null = signed out).
  void userChanged(String? uid) {
    if (uid == _uid) return;
    _uid = uid;
    _start();
  }

  void _start() => unawaited(runNow());

  /// Runs the steps for the current uid unless they already succeeded for
  /// it. Concurrent calls share one run. Completes when that run is done.
  Future<void> runNow() {
    final uid = _uid;
    return _running ??= _run(uid).whenComplete(() {
      _running = null;
      // The user changed while that run was going: run for the new one.
      if (_uid != uid) _start();
    });
  }

  Future<void> _run(String? uid) async {
    if (uid == null || _done.contains(uid)) return;
    try {
      if (!await isOnline()) return;
    } catch (_) {
      return;
    }
    var userDocOk = false;
    try {
      await ensureUserDocument(uid);
      userDocOk = true;
    } catch (e) {
      debugPrint(
        '[KOI] firebase: user doc not created yet '
        '(${syncFailureReason(e)})',
      );
    }
    await ensureSalt(uid);
    try {
      await flush();
    } catch (_) {
      // flush never throws; nothing to report.
    }
    // A sign-out or switch while running must not mark the new uid done.
    if (userDocOk && _uid == uid) _done.add(uid);
  }

  Future<void> dispose() async => _sub?.cancel();
}
