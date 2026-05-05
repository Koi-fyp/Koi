import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:koi_flutter_lib/models/hive_mood_entry_model.dart';
import 'package:koi_flutter_lib/storage/hive_manager.dart';
import 'package:koi_flutter_lib/storage/repositories/mood_repository.dart';

HiveMoodEntry makeEntry(String id, String userId, DateTime ts) => HiveMoodEntry(
  id: id,
  userId: userId,
  timestamp: ts,
  moodRating: 3,
  connectionRating: 3,
  energyRating: 3,
  lonelinessScore: 0.5,
  synced: false,
);

void main() {
  late Directory tempDir;
  late MoodRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(HiveMoodEntryAdapter());
    await Hive.openBox<HiveMoodEntry>(HiveManager.moodEntriesBox);
    repo = MoodRepository();
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  test('saveEntry and getEntry round-trip', () async {
    final entry = makeEntry('e1', 'user1', DateTime(2024, 1, 1));
    await repo.saveEntry(entry);
    expect(repo.getEntry('e1'), isNotNull);
  });

  test('getByUser returns sorted entries', () async {
    await repo.saveEntry(makeEntry('e2', 'user2', DateTime(2024, 1, 2)));
    await repo.saveEntry(makeEntry('e3', 'user2', DateTime(2024, 1, 1)));
    final entries = repo.getByUser('user2');
    expect(entries.length, equals(2));
    expect(entries[0].id, equals('e3'));
  });

  test('getByUserInRange filters correctly', () async {
    await repo.saveEntry(makeEntry('e4', 'user3', DateTime(2024, 1, 5)));
    await repo.saveEntry(makeEntry('e5', 'user3', DateTime(2024, 1, 15)));
    await repo.saveEntry(makeEntry('e6', 'user3', DateTime(2024, 1, 25)));
    final range = repo.getByUserInRange('user3', DateTime(2024, 1, 10), DateTime(2024, 1, 20));
    expect(range.length, equals(1));
    expect(range[0].id, equals('e5'));
  });

  test('getUnsynced returns unsynced only', () async {
    await repo.saveEntry(makeEntry('e7', 'user4', DateTime(2024, 1, 1)));
    final entry2 = makeEntry('e8', 'user4', DateTime(2024, 1, 2))..synced = true;
    await repo.saveEntry(entry2);
    expect(repo.getUnsynced().length, equals(1));
  });

  test('markSynced updates flag', () async {
    await repo.saveEntry(makeEntry('e9', 'user5', DateTime(2024, 1, 1)));
    await repo.markSynced('e9');
    expect(repo.getEntry('e9')!.synced, isTrue);
  });
}
