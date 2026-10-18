import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:koi_flutter_lib/storage/repositories/user_repository.dart';

import '../avatar/avatar_state.dart';
import '../onboarding/onboarding_service.dart';

/// userPreferences.ts:7 validTime(): 'HH:mm', 00:00-23:59.
bool validTime(Object? value) =>
    value is String && RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value);

/// The values the Settings page shows and changes, saved to the same local
/// user record that onboarding writes (web 223e97c saves them to its local
/// IndexedDB record, lib/preferences/userPreferences.ts:16-49).
///
/// A null [language], [notificationsEnabled] or [notificationTime] means
/// nothing is saved (web shows "No … saved" for an undefined field,
/// settings/page.tsx:136, :183, :192).
@immutable
class SettingsPrefs {
  const SettingsPrefs({
    this.companion = defaultCompanion,
    this.displayName = '',
    this.language,
    this.notificationsEnabled,
    this.notificationTime,
    this.storedAvatar,
  });

  static const String defaultCompanion = 'koi';

  /// 'aisha' | 'raza' | 'koi' (web UserRecord.companion).
  final String companion;

  /// AvatarPicker "Companion nickname (optional, stored locally)", web
  /// UserPreferences.displayName (userPreferences.ts:4). Local only.
  final String displayName;

  /// 'en' | 'ur' (web UserRecord.language).
  final String? language;
  final bool? notificationsEnabled;

  /// 'HH:mm' (HiveUser.notificationTime, web UserRecord.notificationTime).
  final String? notificationTime;

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
    String? displayName,
    String? language,
    bool? notificationsEnabled,
    String? notificationTime,
  }) => SettingsPrefs(
    companion: companion ?? this.companion,
    displayName: displayName ?? this.displayName,
    language: language ?? this.language,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    notificationTime: notificationTime ?? this.notificationTime,
    storedAvatar: storedAvatar,
  );
}

/// userPreferences.ts:52-58 reminderStatus(): a local clock comparison only.
/// No delivery, completion or scheduler is implied.
String reminderStatus(SettingsPrefs? prefs, DateTime now) {
  if (prefs?.notificationsEnabled != true) {
    return prefs?.notificationsEnabled == false
        ? 'Preference off; no notifications scheduled.'
        : 'No check-in preference saved.';
  }
  final time = prefs!.notificationTime;
  if (time == null || !validTime(time)) {
    return 'Choose a preferred time. Message delivery is unavailable.';
  }
  String two(int v) => v.toString().padLeft(2, '0');
  final clock = '${two(now.hour)}:${two(now.minute)}';
  final reached = clock.compareTo(time) >= 0;
  return '${reached ? 'Preferred time reached' : 'Preferred time later today'}'
      ' ($time, device time). No message is scheduled.';
}

abstract class SettingsPrefsStore {
  /// Stored prefs for [uid], or the defaults when nothing is stored.
  Future<SettingsPrefs> load(String uid);

  /// Throws when nothing could be saved, so the page never reports a save
  /// that didn't happen (web settings/page.tsx:37-38).
  Future<void> save(String uid, SettingsPrefs prefs);
}

/// Reads/writes flutter_lib's encrypted `users` Hive box, using the same
/// fields and `settings` JSON keys as [HiveUserOnboardingWriter].
class HiveUserSettingsStore implements SettingsPrefsStore {
  HiveUserSettingsStore(this._repo);
  final UserRepository _repo;

  /// Key inside HiveUser.settings for the companion nickname (web field
  /// name, userPreferences.ts:4).
  static const String displayNameKey = 'displayName';

  /// The old "Your Name (Optional)" key. It held the user's own name, not a
  /// companion nickname, so it is never read and is removed on the next save
  /// (decision 2026-10-18).
  static const String legacyNameKey = 'name';

  /// AvatarPicker.tsx:191 maxLength, userPreferences.ts:35.
  static const int maxDisplayName = 64;

  @override
  Future<SettingsPrefs> load(String uid) async {
    final user = await _repo.getUser(uid);
    if (user == null) return const SettingsPrefs();
    final s = HiveUserOnboardingWriter.decodeSettings(user.settings);
    final companion = s[HiveUserOnboardingWriter.companionKey];
    final displayName = s[displayNameKey];
    final enabled = s[HiveUserOnboardingWriter.notificationsEnabledKey];
    // avatarPreference.ts:20-28 resolveRepresentation(): companion first,
    // then the avatar of an avatar-only record.
    final resolved = CompanionAvatar.resolve(
      companion: companion is String ? companion : null,
      avatar: user.avatarType,
    );
    return SettingsPrefs(
      companion: resolved?.companion ?? SettingsPrefs.defaultCompanion,
      displayName: displayName is String ? displayName : '',
      language: user.language,
      notificationsEnabled: enabled is bool ? enabled : null,
      notificationTime: user.notificationTime,
      storedAvatar: user.avatarType,
    );
  }

  @override
  Future<void> save(String uid, SettingsPrefs prefs) async {
    validate(prefs);
    final user = await _repo.getUser(uid);
    // Onboarding creates the record; without it there is nothing to update.
    if (user == null) throw StateError('No local user record to update.');
    final settings = {
      ...HiveUserOnboardingWriter.decodeSettings(user.settings),
      HiveUserOnboardingWriter.companionKey: prefs.companion,
      HiveUserOnboardingWriter.notificationsEnabledKey:
          ?prefs.notificationsEnabled,
      displayNameKey: prefs.displayName.trim(),
    }..remove(legacyNameKey);
    user
      ..language = prefs.language ?? user.language
      ..notificationTime = prefs.notificationTime ?? user.notificationTime
      ..avatarType = prefs.avatar.avatarId
      ..settings = jsonEncode(settings);
    await _repo.saveUser(user);
    // Firestore: SyncingSettingsPrefsStore (core/firestore/profile_sync.dart)
    // wraps this store when Firebase is configured.
  }

  /// saveUserPreferences() checks (userPreferences.ts:22-37).
  static void validate(SettingsPrefs prefs) {
    final language = prefs.language;
    if (language != null && language != 'en' && language != 'ur') {
      throw ArgumentError('Choose a supported language.');
    }
    final time = prefs.notificationTime;
    if (time != null && !validTime(time)) {
      throw ArgumentError('Choose a valid time.');
    }
    final name = prefs.displayName;
    if (name.trim().runes.length > maxDisplayName ||
        RegExp(r'[\u0000-\u001f\u007f]').hasMatch(name)) {
      throw ArgumentError('Use a nickname of up to 64 characters.');
    }
  }
}

/// In-memory store for tests.
class MemorySettingsPrefsStore implements SettingsPrefsStore {
  MemorySettingsPrefsStore([Map<String, SettingsPrefs>? initial])
    : values = {...?initial};
  final Map<String, SettingsPrefs> values;

  /// When set, [save] throws it (for failure feedback tests).
  Object? saveError;

  @override
  Future<SettingsPrefs> load(String uid) async =>
      values[uid] ?? const SettingsPrefs();

  @override
  Future<void> save(String uid, SettingsPrefs prefs) async {
    final error = saveError;
    if (error != null) throw error;
    values[uid] = prefs;
  }
}
