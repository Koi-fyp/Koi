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
    this.avatarType = AvatarType.male,
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

  /// Mobile-only "Avatar: Male / Female" row; HiveUser.avatarType, which
  /// onboarding sets to male_human (Q8). Web Settings has no such row.
  final AvatarType avatarType;

  SettingsPrefs copyWith({
    String? companion,
    String? name,
    String? language,
    bool? notificationsEnabled,
    AvatarType? avatarType,
  }) => SettingsPrefs(
    companion: companion ?? this.companion,
    name: name ?? this.name,
    language: language ?? this.language,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    avatarType: avatarType ?? this.avatarType,
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
    return SettingsPrefs(
      companion: companion is String
          ? companion
          : SettingsPrefs.defaultCompanion,
      name: name is String ? name : '',
      language: user.language,
      notificationsEnabled: enabled is bool ? enabled : true,
      avatarType: AvatarType.fromStored(user.avatarType),
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
      ..avatarType = prefs.avatarType.stored
      ..settings = jsonEncode({
        ...HiveUserOnboardingWriter.decodeSettings(user.settings),
        HiveUserOnboardingWriter.companionKey: prefs.companion,
        HiveUserOnboardingWriter.notificationsEnabledKey:
            prefs.notificationsEnabled,
        nameKey: prefs.name,
      });
    await _repo.saveUser(user);
    // TODO(firebase): onboarding.ts merges profile fields into users/{uid}
    // in Firestore. Web Settings writes nothing, so mobile doesn't either
    // until the team decides Settings changes should sync.
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
