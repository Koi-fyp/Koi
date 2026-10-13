import 'package:flutter/foundation.dart';

import 'key_value_store.dart';

/// Mobile equivalent of the web's `koi_onboarding_complete` localStorage flag
/// (repos/koi-backend/nextjs_app/src/lib/onboarding.ts: completeOnboarding()
/// writes 'true' first, isOnboardingComplete() reads it synchronously).
///
/// Stored in a plain (unencrypted) Hive box, `koi_local_prefs`, under the same
/// key and value as web. Why Hive and not flutter_secure_storage: the flag is
/// not secret (web keeps it in plain localStorage), Hive is already the app's
/// local store via flutter_lib, and an open Hive box can be read
/// synchronously, matching isOnboardingComplete(). This box is separate from
/// flutter_lib's encrypted boxes (users, messages, …).
///
/// Like web, signing out does not clear it.
class OnboardingStore extends ChangeNotifier {
  OnboardingStore(this._store);

  static const String boxName = 'koi_local_prefs';
  static const String key = 'koi_onboarding_complete'; // onboarding.ts

  final KeyValueStore _store;

  /// onboarding.ts isOnboardingComplete(): `=== 'true'`.
  bool get isComplete => _store.get(key) == 'true';

  /// The first step of onboarding.ts completeOnboarding(). The local user
  /// record and Firestore writes come in Prompt 5.
  Future<void> markComplete() async {
    await _store.put(key, 'true');
    notifyListeners();
  }
}
