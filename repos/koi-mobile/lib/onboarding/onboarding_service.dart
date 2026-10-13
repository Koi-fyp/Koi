import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:koi_flutter_lib/models/hive_user_model.dart';
import 'package:koi_flutter_lib/storage/repositories/user_repository.dart';

import '../core/onboarding_store.dart';

/// Avatar ids, from `AvatarId` in
/// repos/koi-backend/nextjs_app/src/app/onboarding/page.tsx.
///
/// Q7 (2026-10-13): mobile drops 'fox' and defaults to 'male_human', per the
/// locked docs decision. NOTE: the web still offers 'fox' (AvatarStep.tsx) and
/// defaults to it (page.tsx `avatar || 'fox'`); the web should be updated.
abstract final class KoiAvatarId {
  static const String femaleHuman = 'female_human';
  static const String maleHuman = 'male_human';

  /// Mobile default (web: 'fox', see class doc).
  static const String fallback = maleHuman;
}

/// onboarding.ts `OnboardingData`, same field names and ids as web:
/// companion 'aisha' | 'raza' | 'koi', language 'en' | 'ur',
/// notificationTime 'HH:mm', notificationsEnabled.
@immutable
class OnboardingData {
  const OnboardingData({
    required this.avatar,
    required this.companion,
    required this.language,
    required this.notificationTime,
    required this.notificationsEnabled,
  });

  final String avatar;
  final String companion;
  final String language;
  final String notificationTime;
  final bool notificationsEnabled;
}

/// Local user-record write (web: the IndexedDB `db.users` add/update).
abstract class OnboardingUserWriter {
  Future<void> save(String uid, OnboardingData data);
}

/// Writes through flutter_lib's UserRepository (encrypted `users` Hive box).
///
/// HiveUser has fields for avatar, language, notificationTime and createdAt.
/// It has none for companion, notificationsEnabled or onboardingComplete, so
/// those go into its `settings` JSON string (decision 2026-10-13: no
/// flutter_lib change).
class HiveUserOnboardingWriter implements OnboardingUserWriter {
  HiveUserOnboardingWriter(this._repo, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final UserRepository _repo;
  final DateTime Function() _now;

  /// Keys inside HiveUser.settings, named as in web's UserRecord (lib/db.ts).
  static const String companionKey = 'companion';
  static const String notificationsEnabledKey = 'notificationsEnabled';
  static const String onboardingCompleteKey = 'onboardingComplete';

  @override
  Future<void> save(String uid, OnboardingData data) async {
    final existing = await _repo.getUser(uid);
    final settings = <String, dynamic>{
      if (existing != null) ...decodeSettings(existing.settings),
      companionKey: data.companion,
      notificationsEnabledKey: data.notificationsEnabled,
      onboardingCompleteKey: true,
    };
    if (existing == null) {
      // onboarding.ts: db.users.add({ uid, ...data, onboardingComplete: true,
      // createdAt }). Counters start at zero.
      final now = _now();
      await _repo.saveUser(
        HiveUser(
          id: uid,
          createdAt: now,
          lastActive: now,
          avatarType: data.avatar,
          language: data.language,
          notificationTime: data.notificationTime,
          settings: jsonEncode(settings),
          totalConversations: 0,
          totalCheckIns: 0,
          currentStreak: 0,
          longestStreak: 0,
          jigsawPieces: 0,
        ),
      );
    } else {
      // onboarding.ts: db.users.update(existing.id, {...}).
      existing
        ..avatarType = data.avatar
        ..language = data.language
        ..notificationTime = data.notificationTime
        ..settings = jsonEncode(settings);
      await _repo.saveUser(existing);
    }
  }

  static Map<String, dynamic> decodeSettings(String raw) {
    try {
      final v = jsonDecode(raw);
      return v is Map<String, dynamic> ? v : {};
    } catch (_) {
      return {};
    }
  }
}

/// Mirrors onboarding.ts completeOnboarding().
class OnboardingService {
  OnboardingService({
    required this.flag,
    required this.users,
    required this.currentUid,
  });

  final OnboardingStore flag;
  final OnboardingUserWriter users;
  final String? Function() currentUid;

  Future<void> complete(OnboardingData data) async {
    // "Always persist locally first — cloud writes are best-effort"
    await flag.markComplete();

    final uid = currentUid();

    // Local user record (web: IndexedDB). Failure is logged, never thrown.
    try {
      if (uid != null) await users.save(uid, data);
    } catch (e) {
      debugPrint('KOI: local user write failed: $e');
    }

    // TODO(firebase): best-effort Firestore merge, same as onboarding.ts:
    //   users/{uid} ← { profile: { avatar, companion, language,
    //   notificationTime }, onboarding_complete: true }  (SetOptions merge)
    // Firebase is not connected yet. When it is, wrap the write in
    // try/catch so a failure never blocks finishing onboarding.
  }
}
