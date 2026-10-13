import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:koi_flutter_lib/models/hive_user_model.dart';
import 'package:koi_flutter_lib/storage/hive_manager.dart';
import 'package:koi_flutter_lib/storage/repositories/user_repository.dart';
import 'package:koi_mobile/onboarding/onboarding_service.dart';
import 'package:koi_mobile/settings/settings_prefs.dart';

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

  test('no user record → web defaults (koi, "", en, enabled)', () async {
    final p = await HiveUserSettingsStore(repo).load('u1');
    expect(p.companion, 'koi');
    expect(p.name, '');
    expect(p.language, 'en');
    expect(p.notificationsEnabled, isTrue);
  });

  test('reads what onboarding wrote', () async {
    await onboard();
    final p = await HiveUserSettingsStore(repo).load('u1');
    expect(p.companion, 'raza');
    expect(p.language, 'ur');
    expect(p.notificationsEnabled, isFalse);
  });

  test('save updates the same fields and keeps other settings keys', () async {
    await onboard();
    final store = HiveUserSettingsStore(repo);
    await store.save(
      'u1',
      const SettingsPrefs(
        companion: 'aisha',
        name: 'Sara',
        language: 'en',
        notificationsEnabled: true,
      ),
    );
    final user = (await repo.getUser('u1'))!;
    expect(user.language, 'en');
    expect(user.avatarType, 'female_human'); // untouched
    expect(user.notificationTime, '21:15'); // untouched
    final s = jsonDecode(user.settings) as Map<String, dynamic>;
    expect(s['companion'], 'aisha');
    expect(s['notificationsEnabled'], isTrue);
    expect(s['name'], 'Sara');
    expect(s['onboardingComplete'], isTrue); // kept
    final back = await store.load('u1');
    expect(back.name, 'Sara');
    expect(back.companion, 'aisha');
  });

  test('save without a user record writes nothing', () async {
    await HiveUserSettingsStore(repo).save('u1', const SettingsPrefs());
    expect(await repo.getUser('u1'), isNull);
  });
}
