import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:koi_flutter_lib/models/hive_task_model.dart';
import 'package:koi_flutter_lib/storage/hive_manager.dart';
import 'package:koi_flutter_lib/storage/repositories/task_repository.dart';

HiveTask makeTask(String id, String userId) => HiveTask(
  id: id,
  userId: userId,
  type: 'cbt_practice',
  description: 'Do the thing',
  commitmentLevel: 7,
  createdAt: DateTime(2024, 1, 1),
  archived: false,
  synced: false,
);

void main() {
  late Directory tempDir;
  late TaskRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(HiveTaskAdapter());
    await Hive.openBox<HiveTask>(HiveManager.tasksBox);
    repo = TaskRepository();
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  test('saveTask and getTask round-trip', () async {
    await repo.saveTask(makeTask('t1', 'user1'));
    final t = repo.getTask('t1');
    expect(t, isNotNull);
    expect(t!.type, equals('cbt_practice'));
    expect(t.commitmentLevel, equals(7));
  });

  test('getActiveByUser excludes archived tasks', () async {
    await repo.saveTask(makeTask('t2', 'user2'));
    final archived = makeTask('t3', 'user2')..archived = true;
    await repo.saveTask(archived);
    final active = repo.getActiveByUser('user2');
    expect(active.length, equals(1));
    expect(active[0].id, equals('t2'));
  });

  test('completeTask sets completedAt', () async {
    await repo.saveTask(makeTask('t4', 'user3'));
    await repo.completeTask('t4');
    expect(repo.getTask('t4')!.completedAt, isNotNull);
  });

  test('getCompletedByUser returns only completed tasks', () async {
    await repo.saveTask(makeTask('t5', 'user4'));
    await repo.saveTask(makeTask('t6', 'user4'));
    await repo.completeTask('t6');
    expect(repo.getCompletedByUser('user4').length, equals(1));
  });

  test('archiveTask sets archived flag', () async {
    await repo.saveTask(makeTask('t7', 'user5'));
    await repo.archiveTask('t7');
    expect(repo.getTask('t7')!.archived, isTrue);
  });

  test('getUnsynced returns only unsynced tasks', () async {
    await repo.saveTask(makeTask('t8', 'user6'));
    final synced = makeTask('t9', 'user6')..synced = true;
    await repo.saveTask(synced);
    expect(repo.getUnsynced().length, equals(1));
    expect(repo.getUnsynced()[0].id, equals('t8'));
  });

  test('markSynced updates synced to true', () async {
    await repo.saveTask(makeTask('t10', 'user7'));
    await repo.markSynced('t10');
    expect(repo.getTask('t10')!.synced, isTrue);
  });

  test('deleteTask removes task', () async {
    await repo.saveTask(makeTask('t11', 'user8'));
    await repo.deleteTask('t11');
    expect(repo.getTask('t11'), isNull);
  });
}
