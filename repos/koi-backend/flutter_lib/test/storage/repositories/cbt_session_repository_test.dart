import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:koi_flutter_lib/models/hive_cbt_session_model.dart';
import 'package:koi_flutter_lib/storage/hive_manager.dart';
import 'package:koi_flutter_lib/storage/repositories/cbt_session_repository.dart';

HiveCBTSession makeSession(String id, String userId) => HiveCBTSession(
  id: id,
  userId: userId,
  moduleType: 'reframing',
  startedAt: DateTime(2024, 1, 1),
  jigsawPiecesAwarded: 5,
  synced: false,
);

void main() {
  late Directory tempDir;
  late CBTSessionRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(HiveCBTSessionAdapter());
    await Hive.openBox<HiveCBTSession>(HiveManager.cbtSessionsBox);
    repo = CBTSessionRepository();
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  test('saveSession and getSession round-trip', () async {
    final session = makeSession('s1', 'user1');
    await repo.saveSession(session);
    expect(repo.getSession('s1'), isNotNull);
    expect(repo.getSession('s1')!.moduleType, equals('reframing'));
  });

  test('getByUser returns sessions for user', () async {
    await repo.saveSession(makeSession('s2', 'user2'));
    await repo.saveSession(makeSession('s3', 'user2'));
    await repo.saveSession(makeSession('s4', 'user3'));
    expect(repo.getByUser('user2').length, equals(2));
  });

  test('completeSession sets completedAt and quality fields', () async {
    await repo.saveSession(makeSession('s5', 'user1'));
    await repo.completeSession('s5', qualityScore: 0.85, userInsights: 'good insight');
    final s = repo.getSession('s5');
    expect(s!.completedAt, isNotNull);
    expect(s.qualityScore, equals(0.85));
    expect(s.userInsights, equals('good insight'));
  });

  test('getCompletedByUser excludes incomplete sessions', () async {
    await repo.saveSession(makeSession('s6', 'user4'));
    await repo.saveSession(makeSession('s7', 'user4'));
    await repo.completeSession('s7');
    expect(repo.getCompletedByUser('user4').length, equals(1));
    expect(repo.getCompletedByUser('user4')[0].id, equals('s7'));
  });

  test('getUnsynced returns only unsynced sessions', () async {
    await repo.saveSession(makeSession('s8', 'user5'));
    final synced = makeSession('s9', 'user5')..synced = true;
    await repo.saveSession(synced);
    expect(repo.getUnsynced().length, equals(1));
    expect(repo.getUnsynced()[0].id, equals('s8'));
  });

  test('markSynced sets synced flag to true', () async {
    await repo.saveSession(makeSession('s10', 'user6'));
    await repo.markSynced('s10');
    expect(repo.getSession('s10')!.synced, isTrue);
  });

  test('deleteSession removes session', () async {
    await repo.saveSession(makeSession('s11', 'user7'));
    await repo.deleteSession('s11');
    expect(repo.getSession('s11'), isNull);
  });
}
