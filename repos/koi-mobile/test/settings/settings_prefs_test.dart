import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:koi_flutter_lib/models/hive_user_model.dart';
import 'package:koi_flutter_lib/storage/hive_manager.dart';
import 'package:koi_flutter_lib/storage/repositories/user_repository.dart';
import 'package:koi_mobile/app/providers.dart';
import 'package:koi_mobile/avatar/avatar_providers.dart';
import 'package:koi_mobile/avatar/avatar_state.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/core/firestore/profile_sync.dart';
import 'package:koi_mobile/core/sync_queue.dart';
import 'package:koi_mobile/onboarding/onboarding_service.dart';
import 'package:koi_mobile/settings/settings_prefs.dart';

import '../support/fake_auth.dart';

class _Queue implements SyncQueue {
  final items = <SyncItem>[];
  @override
  void enqueue(SyncItem item) => items.add(item);
}

void main() {
  late Directory dir;
  final repo = UserRepository();

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('koi_settings_test');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(HiveUserAdapter());
    await Hive.openBox<HiveUser>(HiveManager.usersBox);
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Future<void> onboard() => HiveUserOnboardingWriter(repo).save(
    'u1',
    const OnboardingData(
      avatar: 'female_human',
      companion: 'raza',
      language: 'ur',
      notificationTime: '21:15',
      notificationsEnabled: false,
    ),
  );

  test('ATC-M1-21 no user record → nothing saved (koi, no language/check-in)', () async {
    final p = await HiveUserSettingsStore(repo).load('u1');
    expect(p.companion, 'koi');
    expect(p.displayName, '');
    expect(p.language, isNull);
    expect(p.notificationsEnabled, isNull);
    expect(p.notificationTime, isNull);
  });

  test('ATC-M1-21 reads what onboarding wrote', () async {
    await onboard();
    final p = await HiveUserSettingsStore(repo).load('u1');
    expect(p.companion, 'raza');
    expect(p.language, 'ur');
    expect(p.notificationsEnabled, isFalse);
    expect(p.notificationTime, '21:15'); // the real saved time (G13)
  });

  test('ATC-M1-21 save updates the same fields and keeps other settings keys', () async {
    await onboard();
    final store = HiveUserSettingsStore(repo);
    await store.save(
      'u1',
      const SettingsPrefs(
        companion: 'aisha',
        displayName: ' Sara ',
        language: 'en',
        notificationsEnabled: true,
        notificationTime: '07:30',
      ),
    );
    final user = (await repo.getUser('u1'))!;
    expect(user.language, 'en');
    expect(user.avatarType, 'female_human');
    expect(user.notificationTime, '07:30');
    final s = jsonDecode(user.settings) as Map<String, dynamic>;
    expect(s['companion'], 'aisha');
    expect(s['notificationsEnabled'], isTrue);
    expect(s['displayName'], 'Sara'); // trimmed, web key
    expect(s.containsKey('name'), isFalse);
    expect(s['onboardingComplete'], isTrue); // kept
    final back = await store.load('u1');
    expect(back.displayName, 'Sara');
    expect(back.companion, 'aisha');
  });

  test(
    'ATC-M1-22 the avatar follows the companion; save stores the matching one',
    () async {
      await onboard(); // raza saved with a mismatched female_human
      final store = HiveUserSettingsStore(repo);
      final p = await store.load('u1');
      expect(p.avatar, CompanionAvatar.raza);
      expect(p.storedAvatar, 'female_human');
      expect(p.avatarOutOfDate, isTrue);
      await store.save('u1', p);
      expect((await repo.getUser('u1'))!.avatarType, 'male_human');
      expect((await store.load('u1')).avatarOutOfDate, isFalse);

      await store.save('u1', p.copyWith(companion: 'koi'));
      expect((await repo.getUser('u1'))!.avatarType, 'fox');
      await store.save('u1', p.copyWith(companion: 'aisha'));
      expect((await repo.getUser('u1'))!.avatarType, 'female_human');
    },
  );

  test('ATC-M1-22 legacy record without a companion: avatar picks it', () async {
    final now = DateTime(2026);
    await repo.saveUser(
      HiveUser(
        id: 'u1',
        createdAt: now,
        lastActive: now,
        avatarType: 'female_human',
        language: 'en',
        settings: '{}',
        totalConversations: 0,
        totalCheckIns: 0,
        currentStreak: 0,
        longestStreak: 0,
        jigsawPieces: 0,
      ),
    );
    final p = await HiveUserSettingsStore(repo).load('u1');
    expect(p.companion, 'aisha');
    expect(p.avatarOutOfDate, isFalse);
  });

  group('ATC-M1-22 existing user migration (selectedAvatarProvider)', () {
    // A record from before Prompt 19: Aisha chosen, avatar saved as
    // male_human (the old onboarding fallback).
    Future<void> oldRecord(String companion) =>
        HiveUserOnboardingWriter(repo).save(
          'u1',
          OnboardingData(
            avatar: 'male_human',
            companion: companion,
            language: 'en',
            notificationTime: '20:00',
            notificationsEnabled: true,
          ),
        );

    Future<(CompanionAvatar?, List<SyncItem>)> launch() async {
      final queue = _Queue();
      final container = ProviderContainer(
        overrides: [
          authServiceProvider.overrideWith(
            (ref) => FakeAuthService(
              fakeUser: const KoiUser(uid: 'u1', isAnonymous: true),
            ),
          ),
          settingsPrefsStoreProvider.overrideWithValue(
            SyncingSettingsPrefsStore(HiveUserSettingsStore(repo), queue),
          ),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(selectedAvatarProvider, (_, _) {});
      addTearDown(sub.close);
      // Load, then the repair save (real Hive I/O).
      for (var i = 0; i < 20 && sub.read().isLoading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return (sub.read().valueOrNull, queue.items);
    }

    test('Aisha + male_human → female on next launch, stored once', () async {
      await oldRecord('aisha');
      final (avatar, items) = await launch();
      expect(avatar, CompanionAvatar.aisha);
      expect(avatar!.model, AvatarType.female);
      // Local record repaired, onboarding not redone.
      final user = (await repo.getUser('u1'))!;
      expect(user.avatarType, 'female_human');
      expect(jsonDecode(user.settings)['onboardingComplete'], isTrue);
      // One Firestore profile merge with the matching pair.
      final profile = items.single.data['profile'] as Map;
      expect(profile['avatar'], 'female_human');
      expect(profile['companion'], 'aisha');

      // Second launch: already matching, nothing re-sent.
      final (again, items2) = await launch();
      expect(again, CompanionAvatar.aisha);
      expect(items2, isEmpty);
    });

    test('Koi + male_human → fox (no model), profile.avatar fox', () async {
      await oldRecord('koi');
      final (avatar, items) = await launch();
      expect(avatar, CompanionAvatar.koi);
      expect(avatar!.model, isNull);
      expect((await repo.getUser('u1'))!.avatarType, 'fox');
      expect((items.single.data['profile'] as Map)['avatar'], 'fox');
    });

    test('Raza + male_human already matches: no write', () async {
      await oldRecord('raza');
      final (avatar, items) = await launch();
      expect(avatar, CompanionAvatar.raza);
      expect(items, isEmpty);
    });
  });

  test('ATC-M1-21 save without a user record throws and writes nothing', () async {
    await expectLater(
      HiveUserSettingsStore(repo).save('u1', const SettingsPrefs()),
      throwsStateError,
    );
    expect(await repo.getUser('u1'), isNull);
  });

  test('ATC-M1-21 old "Your Name" value is not shown as a nickname and is removed '
      'on save (decision 2026-10-18)', () async {
    await onboard();
    final user = (await repo.getUser('u1'))!;
    user.settings = jsonEncode({
      ...jsonDecode(user.settings) as Map<String, dynamic>,
      'name': 'Irsa',
    });
    await repo.saveUser(user);
    final store = HiveUserSettingsStore(repo);
    final p = await store.load('u1');
    expect(p.displayName, '');
    await store.save('u1', p);
    final s = jsonDecode((await repo.getUser('u1'))!.settings) as Map;
    expect(s.containsKey('name'), isFalse);
    expect(s['displayName'], '');
  });

  test(
    'ATC-M1-21 nothing saved stays unsaved: null fields keep the record values',
    () async {
      await onboard();
      final store = HiveUserSettingsStore(repo);
      await store.save('u1', const SettingsPrefs(companion: 'koi'));
      final user = (await repo.getUser('u1'))!;
      expect(user.language, 'ur');
      expect(user.notificationTime, '21:15');
      final s = jsonDecode(user.settings) as Map;
      expect(s['notificationsEnabled'], isFalse);
    },
  );

  group('ATC-M1-23 validation (userPreferences.ts:22-37)', () {
    Future<void> save(SettingsPrefs p) async {
      await onboard();
      await HiveUserSettingsStore(repo).save('u1', p);
    }

    test(
      'rejects unsupported language, bad time, long or control nickname',
      () async {
        for (final bad in [
          const SettingsPrefs(language: 'fr'),
          const SettingsPrefs(notificationTime: '24:00'),
          const SettingsPrefs(notificationTime: '7:30'),
          SettingsPrefs(displayName: 'x' * 65),
          const SettingsPrefs(displayName: 'a\u0007b'),
        ]) {
          await expectLater(save(bad), throwsArgumentError);
        }
        expect((await repo.getUser('u1'))!.language, 'ur'); // unchanged
      },
    );

    test(
      '64 characters (code points) and surrounding spaces are fine',
      () async {
        await save(SettingsPrefs(displayName: '  ${'🦊' * 64}  '));
        final s = jsonDecode((await repo.getUser('u1'))!.settings) as Map;
        expect(s['displayName'], '🦊' * 64);
      },
    );
  });

  test('ATC-M1-23 validTime and reminderStatus match web', () {
    expect(validTime('00:00'), isTrue);
    expect(validTime('23:59'), isTrue);
    for (final bad in ['24:00', '7:05', '07:60', '', null, 705]) {
      expect(validTime(bad), isFalse, reason: '$bad');
    }
    final noon = DateTime(2026, 1, 1, 12);
    expect(reminderStatus(null, noon), 'No check-in preference saved.');
    expect(
      reminderStatus(const SettingsPrefs(notificationsEnabled: false), noon),
      'Preference off; no notifications scheduled.',
    );
    expect(
      reminderStatus(const SettingsPrefs(notificationsEnabled: true), noon),
      'Choose a preferred time. Message delivery is unavailable.',
    );
    const at = SettingsPrefs(
      notificationsEnabled: true,
      notificationTime: '12:00',
    );
    expect(
      reminderStatus(at, noon),
      'Preferred time reached (12:00, device time). No message is scheduled.',
    );
    expect(
      reminderStatus(at, DateTime(2026, 1, 1, 11, 59)),
      'Preferred time later today (12:00, device time). No message is '
      'scheduled.',
    );
  });
}
