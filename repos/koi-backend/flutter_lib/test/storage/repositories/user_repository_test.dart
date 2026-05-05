import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:koi_flutter_lib/models/hive_user_model.dart';
import 'package:koi_flutter_lib/storage/hive_manager.dart';
import 'package:koi_flutter_lib/storage/repositories/user_repository.dart';

HiveUser makeUser(String id) => HiveUser(
  id: id,
  createdAt: DateTime(2024, 1, 1),
  lastActive: DateTime(2024, 1, 1),
  language: 'en',
  settings: '{}',
  totalConversations: 0,
  totalCheckIns: 0,
  currentStreak: 0,
  longestStreak: 0,
  jigsawPieces: 0,
);

void main() {
  late Directory tempDir;
  late UserRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(HiveUserAdapter());
    await Hive.openBox<HiveUser>(HiveManager.usersBox);
    repo = UserRepository();
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  test('saveUser and getUser round-trip', () async {
    final user = makeUser('u1');
    await repo.saveUser(user);
    final found = await repo.getUser('u1');
    expect(found, isNotNull);
    expect(found!.id, equals('u1'));
    expect(found.language, equals('en'));
  });

  test('getUser returns null for missing id', () async {
    expect(await repo.getUser('missing'), isNull);
  });

  test('deleteUser removes entry', () async {
    final user = makeUser('u2');
    await repo.saveUser(user);
    await repo.deleteUser('u2');
    expect(await repo.getUser('u2'), isNull);
  });

  test('hasUser returns correct value', () async {
    await repo.saveUser(makeUser('u3'));
    expect(repo.hasUser('u3'), isTrue);
    expect(repo.hasUser('none'), isFalse);
  });

  test('updateLastActive changes timestamp', () async {
    final before = DateTime(2024, 1, 1);
    final user = makeUser('u4')..lastActive = before;
    await repo.saveUser(user);
    await repo.updateLastActive('u4');
    final updated = await repo.getUser('u4');
    expect(updated!.lastActive.isAfter(before), isTrue);
  });
}
