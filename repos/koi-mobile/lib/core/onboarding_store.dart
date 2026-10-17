import 'package:flutter/foundation.dart';

import 'key_value_store.dart';

/// Mobile equivalent of the web's `koi_onboarding_complete` localStorage flag
/// (repos/koi-backend/nextjs_app/src/lib/onboarding.ts: completeOnboarding()
/// writes 'true' first, isOnboardingComplete() reads it synchronously).
///
/// Stored in a plain (unencrypted) Hive box, `koi_local_prefs`. Why Hive and
/// not flutter_secure_storage: the flag is not secret (web keeps it in plain
/// localStorage), Hive is already the app's local store via flutter_lib, and
/// an open Hive box can be read synchronously, matching
/// isOnboardingComplete(). This box is separate from flutter_lib's encrypted
/// boxes (users, messages, …).
///
/// Difference from web (decided 2026-10-17): the flag is PER UID, key
/// `koi_onboarding_complete_{uid}`, value 'true'. Web's flag is per browser,
/// so a new uid (new anonymous sign-in, after sign-out, or the switch from
/// the debug uid to a Firebase uid) would skip onboarding and never get a
/// local profile. Like web, signing out does not clear it, so the same uid
/// signing back in still skips onboarding.
class OnboardingStore extends ChangeNotifier {
  OnboardingStore(this._store);

  static const String boxName = 'koi_local_prefs';

  /// onboarding.ts key. Mobile uses it as the prefix of the per-uid key, and
  /// a value stored under it alone is the old per-device flag
  /// (see [migrateDeviceFlag]).
  static const String key = 'koi_onboarding_complete';

  static String keyFor(String uid) => '${key}_$uid';

  final KeyValueStore _store;

  /// onboarding.ts isOnboardingComplete() (`=== 'true'`), for [uid]. Nobody
  /// signed in → false.
  bool isCompleteFor(String? uid) =>
      uid != null && _store.get(keyFor(uid)) == 'true';

  /// The first step of onboarding.ts completeOnboarding(), for [uid].
  Future<void> markComplete(String uid) async {
    await _store.put(keyFor(uid), 'true');
    notifyListeners();
  }

  /// One-time move of the old per-device flag (builds before 2026-10-17).
  /// Only the debug stand-in could have set it, so it goes to the persisted
  /// debug uid ([debugUid], null if none) and the device-wide key is removed.
  /// Any other uid (e.g. a new Firebase uid) then runs onboarding.
  Future<void> migrateDeviceFlag(String? debugUid) async {
    final legacy = _store.get(key);
    if (legacy == null) return;
    if (legacy == 'true' && debugUid != null) {
      await _store.put(keyFor(debugUid), 'true');
    }
    await _store.delete(key);
  }
}
