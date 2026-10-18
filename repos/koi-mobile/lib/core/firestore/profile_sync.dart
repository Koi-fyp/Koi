import '../../onboarding/onboarding_service.dart';
import '../../settings/settings_prefs.dart';
import '../sync_queue.dart';

/// users/{uid} profile merges, queued at priority 4 (sync.ts tasks/user).
/// Field names are the ones firestore.rules.proposed allows
/// (origin/feat/exercise-director-modal): profile.{avatar, companion,
/// language, notificationTime}, onboarding_complete,
/// settings.notifications_enabled. The Settings "name" is local only and is
/// never written.

/// onboarding.ts completeOnboarding(): `{ profile: { avatar, companion,
/// language, notificationTime }, onboarding_complete: true }` (merge), plus
/// settings.notifications_enabled (decided 2026-10-17; web sends nothing).
SyncItem onboardingProfileItem(String uid, OnboardingData d) => SyncItem(
  collection: 'users',
  docId: uid,
  data: {
    'profile': {
      'avatar': d.avatar,
      'companion': d.companion,
      'language': d.language,
      'notificationTime': d.notificationTime,
    },
    'onboarding_complete': true,
    'settings': {'notifications_enabled': d.notificationsEnabled},
  },
  priority: 4,
);

/// Settings changes (mobile-only; web Settings writes nothing to Firestore).
/// avatar always matches companion (aisha → 'female_human', raza →
/// 'male_human', koi → 'fox'), as web saveAvatarPreference writes the pair
/// (223e97c lib/avatar/avatarPreference.ts:41-46).
SyncItem settingsProfileItem(String uid, SettingsPrefs p) => SyncItem(
  collection: 'users',
  docId: uid,
  data: {
    'profile': {
      'avatar': p.avatar.avatarId,
      'companion': p.companion,
      'language': p.language,
    },
    'settings': {'notifications_enabled': p.notificationsEnabled},
  },
  priority: 4,
);

/// Saves Settings locally (as before), then queues the Firestore merge.
class SyncingSettingsPrefsStore implements SettingsPrefsStore {
  SyncingSettingsPrefsStore(this._local, this._queue);

  final SettingsPrefsStore _local;
  final SyncQueue _queue;

  @override
  Future<SettingsPrefs> load(String uid) => _local.load(uid);

  @override
  Future<void> save(String uid, SettingsPrefs prefs) async {
    await _local.save(uid, prefs);
    _queue.enqueue(settingsProfileItem(uid, prefs));
  }
}
