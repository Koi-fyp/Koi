import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:koi_flutter_lib/models/hive_user_model.dart';
import 'package:koi_flutter_lib/storage/hive_manager.dart';
import 'package:koi_flutter_lib/storage/repositories/user_repository.dart';
import 'package:koi_mobile/core/key_value_store.dart';
import 'package:koi_mobile/core/onboarding_store.dart';
import 'package:koi_mobile/onboarding/onboarding_service.dart';

import '../support/fake_auth.dart';

const _data = OnboardingData(
  avatar: 'male_human',
  companion: 'aisha',
  language: 'ur',
  notificationTime: '21:15',
  notificationsEnabled: false,
);

void main() {
  group('OnboardingService (completeOnboarding)', () {
    test('sets the local flag first, then writes the user record', () async {
      final kv = MemoryKeyValueStore();
      final flag = OnboardingStore(kv);
      final order = <String>[];
      flag.addListener(() => order.add('flag'));
      final users = _OrderWriter(order, kv);

      await OnboardingService(
        flag: flag,
        users: users,
        currentUid: () => 'u1',
      ).complete(_data);

      expect(order, ['flag', 'user(flag=true)']);
    });

    test('a failing local write is logged, never blocks completion', () async {
      final flag = OnboardingStore(MemoryKeyValueStore());
      await OnboardingService(
        flag: flag,
        users: RecordingUserWriter(fail: true),
        currentUid: () => 'u1',
      ).complete(_data); // must not throw
      expect(flag.isComplete, isTrue);
    });

    test('no uid: flag set, no user record (web `if (uid)`)', () async {
      final flag = OnboardingStore(MemoryKeyValueStore());
      final users = RecordingUserWriter();
      await OnboardingService(
        flag: flag,
        users: users,
        currentUid: () => null,
      ).complete(_data);
      expect(flag.isComplete, isTrue);
      expect(users.saved, isEmpty);
    });
  });

  group('HiveUserOnboardingWriter (flutter_lib UserRepository)', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('koi_hive_test');
      Hive.init(dir.path);
      if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(HiveUserAdapter());
      await Hive.openBox<HiveUser>(HiveManager.usersBox);
    });

    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test(
      'creates a HiveUser; extra web fields go into settings JSON',
      () async {
        final now = DateTime.utc(2026, 10, 13, 12);
        await HiveUserOnboardingWriter(
          UserRepository(),
          now: () => now,
        ).save('u1', _data);

        final u = (await UserRepository().getUser('u1'))!;
        expect(u.id, 'u1');
        expect(u.avatarType, 'male_human');
        expect(u.language, 'ur');
        expect(u.notificationTime, '21:15');
        expect(u.createdAt, now);
        expect(jsonDecode(u.settings), {
          'companion': 'aisha',
          'notificationsEnabled': false,
          'onboardingComplete': true,
        });
      },
    );

    test('updates an existing user and keeps other settings keys', () async {
      final repo = UserRepository();
      final created = DateTime.utc(2025, 1, 1);
      await repo.saveUser(
        HiveUser(
          id: 'u1',
          createdAt: created,
          lastActive: created,
          language: 'en',
          settings: jsonEncode({'theme': 'x', 'companion': 'koi'}),
          totalConversations: 4,
          totalCheckIns: 0,
          currentStreak: 0,
          longestStreak: 0,
          jigsawPieces: 0,
        ),
      );

      await HiveUserOnboardingWriter(repo).save('u1', _data);

      final u = (await repo.getUser('u1'))!;
      expect(u.createdAt, created); // update, not re-create
      expect(u.totalConversations, 4);
      expect(u.language, 'ur');
      expect(jsonDecode(u.settings), {
        'theme': 'x',
        'companion': 'aisha',
        'notificationsEnabled': false,
        'onboardingComplete': true,
      });
    });
  });
}

class _OrderWriter implements OnboardingUserWriter {
  _OrderWriter(this.order, this.kv);
  final List<String> order;
  final MemoryKeyValueStore kv;

  @override
  Future<void> save(String uid, OnboardingData data) async {
    order.add('user(flag=${kv.values[OnboardingStore.key]})');
  }
}
