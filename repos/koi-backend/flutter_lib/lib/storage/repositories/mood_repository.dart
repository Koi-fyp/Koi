import 'package:hive/hive.dart';
import '../hive_manager.dart';
import '../../models/hive_mood_entry_model.dart';

class MoodRepository {
  Box<HiveMoodEntry> get _box => HiveManager.moodEntries;

  Future<void> saveEntry(HiveMoodEntry entry) async =>
      _box.put(entry.id, entry);

  HiveMoodEntry? getEntry(String id) => _box.get(id);

  List<HiveMoodEntry> getByUser(String userId) {
    return _box.values
        .where((e) => e.userId == userId)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  List<HiveMoodEntry> getByUserInRange(
      String userId, DateTime from, DateTime to) {
    return _box.values
        .where((e) =>
            e.userId == userId &&
            !e.timestamp.isBefore(from) &&
            !e.timestamp.isAfter(to))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  List<HiveMoodEntry> getUnsynced() =>
      _box.values.where((e) => !e.synced).toList();

  Future<void> markSynced(String id) async {
    final entry = _box.get(id);
    if (entry == null) return;
    entry.synced = true;
    await entry.save();
  }

  Future<void> deleteEntry(String id) async => _box.delete(id);
}
