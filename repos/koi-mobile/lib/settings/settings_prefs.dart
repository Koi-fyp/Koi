import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:koi_flutter_lib/storage/repositories/user_repository.dart';

import '../avatar/avatar_state.dart';
import '../onboarding/onboarding_service.dart';

/// The values the Settings page shows and changes.
///
/// Web (src/app/(authenticated)/settings/page.tsx) keeps these in React
/// `useState` only and never saves them. Mobile loads and saves them to the
/// same local user record that onboarding writes (decision 2026-10-13:
/// "persist prefs, rest as web").
@immutable
class SettingsPrefs {
  const SettingsPrefs({
    this.companion = defaultCompanion,
    this.name = '',
    this.language = 'en',
    this.notificationsEnabled = true,
    this.storedAvatar,
  });

  /// page.tsx initial state: useState('koi'), useState(''), useState('en'),
  /// useState(true).
  static const String defaultCompanion = 'koi';

  /// 'aisha' | 'raza' | 'koi' (web UserRecord.companion).
  final String companion;

  /// AvatarPicker "Your Name (Optional)". Not in web's UserRecord (lib/db.ts);
  /// mobile-only key, see [HiveUserSettingsStore.nameKey].
  final String name;

  /// 'en' | 'ur' (web UserRecord.language).
  final String language;
  final bool notificationsEnabled;

  /// HiveUser.avatarType exactly as loaded (null when nothing is stored).
  /// Only used to spot records saved before the companion picked the
  /// avatar; what is shown and saved is always [avatar].
  final String? storedAvatar;

  /// The avatar follows the companion (web 223e97c settings/page.tsx:46-62
  /// saves the matching pair via saveAvatarPreference,
  /// lib/avatar/avatarPreference.ts:41-46).
  CompanionAvatar get avatar =>
      CompanionAvatar.fromCompanion(companion) ?? CompanionAvatar.koi;

  /// A record whose stored avatar doesn't match its companion (before
  /// Prompt 19 onboarding always saved male_human).
  bool get avatarOutOfDate =>
      storedAvatar != null && storedAvatar != avatar.avatarId;

  SettingsPrefs copyWith({
    String? companion,
    String? name,
    String? language,
    bool? notificationsEnabled,
  }) => SettingsPrefs(
    companion: companion ?? this.companion,
    name: name ?? this.name,
    language: language ?? this.language,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    storedAvatar: storedAvatar,
  );
}

abstract class SettingsPrefsStore {
  /// Stored prefs for [uid], or the web defaults when nothing is stored.
  Future<SettingsPrefs> load(String uid);
  Future<void> save(String uid, SettingsPrefs prefs);
}

/// Reads/writes flutter_lib's encrypted `users` Hive box, using the same
/// fields and `settings` JSON keys as [HiveUserOnboardingWriter].
class HiveUserSettingsStore implements SettingsPrefsStore {
  HiveUserSettingsStore(this._repo);
  final UserRepository _repo;

  /// Mobile-only key inside HiveUser.settings for the picker's name field.
  static const String nameKey = 'name';

  @override
  Future<SettingsPrefs> load(String uid) async {
    final user = await _repo.getUser(uid);
    if (user == null) return const SettingsPrefs();
    final s = HiveUserOnboardingWriter.decodeSettings(user.settings);
    final companion = s[HiveUserOnboardingWriter.companionKey];
    final name = s[nameKey];
    final enabled = s[HiveUserOnboardingWriter.notificationsEnabledKey];
    // avatarPreference.ts:20-28 resolveRepresentation(): companion first,
    // then the avatar of an avatar-only record.
    final resolved = CompanionAvatar.resolve(
      companion: companion is String ? companion : null,
      avatar: user.avatarType,
    );
    return SettingsPrefs(
      companion: resolved?.companion ?? SettingsPrefs.defaultCompanion,
      name: name is String ? name : '',
      language: user.language,
      notificationsEnabled: enabled is bool ? enabled : true,
      storedAvatar: user.avatarType,
    );
  }

  @override
  Future<void> save(String uid, SettingsPrefs prefs) async {
    final user = await _repo.getUser(uid);
    if (user == null) {
      // Onboarding creates the record; without it there is nothing to update.
      debugPrint('KOI: settings not saved, no local user record');
      return;
    }
    user
      ..language = prefs.language
      ..avatarType = prefs.avatar.avatarId
      ..settings = jsonEncode({
        ...HiveUserOnboardingWriter.decodeSettings(user.settings),
        HiveUserOnboardingWriter.companionKey: prefs.companion,
        HiveUserOnboardingWriter.notificationsEnabledKey:
            prefs.notificationsEnabled,
        nameKey: prefs.name,
      });
    await _repo.saveUser(user);
    // Firestore: SyncingSettingsPrefsStore (core/firestore/profile_sync.dart)
    // wraps this store when Firebase is configured.
  }
}

/// In-memory store for tests.
class MemorySettingsPrefsStore implements SettingsPrefsStore {
  MemorySettingsPrefsStore([Map<String, SettingsPrefs>? initial])
    : values = {...?initial};
  final Map<String, SettingsPrefs> values;

  @override
  Future<SettingsPrefs> load(String uid) async =>
      values[uid] ?? const SettingsPrefs();

  @override
  Future<void> save(String uid, SettingsPrefs prefs) async =>
      values[uid] = prefs;
}
