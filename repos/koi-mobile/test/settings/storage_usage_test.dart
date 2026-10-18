import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:koi_flutter_lib/storage/hive_manager.dart';
import 'package:koi_mobile/chat/message_record.dart';
import 'package:koi_mobile/core/onboarding_store.dart';
import 'package:koi_mobile/settings/storage_usage.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('koi_storage_test');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  int sizeOf(String name) => File('${dir.path}/$name.hive').lengthSync();

  test('no open box → unavailable (null)', () async {
    expect(await koiHiveBytes(), isNull);
  });

  test('sums the .hive files of KOI boxes, open or closed', () async {
    final messages = await Hive.openBox<String>(HiveMessageStore.boxName);
    await messages.put('a', 'x' * 5000);
    final prefs = await Hive.openBox<String>(OnboardingStore.boxName);
    await prefs.put('k', 'v');
    await prefs.close(); // closed boxes still count
    // Not a KOI box: never counted.
    final other = await Hive.openBox<String>('someone_else');
    await other.put('b', 'y' * 9000);

    final bytes = await koiHiveBytes();
    expect(
      bytes,
      sizeOf(HiveMessageStore.boxName) + sizeOf(OnboardingStore.boxName),
    );
    expect(bytes, greaterThan(5000));
  });

  test('covers flutter_lib boxes and the app boxes', () {
    expect(
      koiHiveBoxNames,
      containsAll([
        HiveManager.usersBox,
        HiveManager.messagesBox,
        HiveManager.moodEntriesBox,
        HiveManager.cbtSessionsBox,
        HiveManager.tasksBox,
        HiveMessageStore.boxName,
        OnboardingStore.boxName,
      ]),
    );
  });
}
