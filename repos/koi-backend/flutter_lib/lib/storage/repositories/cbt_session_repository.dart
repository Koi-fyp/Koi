import 'package:hive/hive.dart';
import '../hive_manager.dart';
import '../../models/hive_cbt_session_model.dart';

class CBTSessionRepository {
  Box<HiveCBTSession> get _box => HiveManager.cbtSessions;

  Future<void> saveSession(HiveCBTSession session) async =>
      _box.put(session.id, session);

  HiveCBTSession? getSession(String id) => _box.get(id);

  List<HiveCBTSession> getByUser(String userId) {
    return _box.values
        .where((s) => s.userId == userId)
        .toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  }

  List<HiveCBTSession> getCompletedByUser(String userId) {
    return _box.values
        .where((s) => s.userId == userId && s.completedAt != null)
        .toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  }

  List<HiveCBTSession> getUnsynced() =>
      _box.values.where((s) => !s.synced).toList();

  Future<void> markSynced(String id) async {
    final session = _box.get(id);
    if (session == null) return;
    session.synced = true;
    await session.save();
  }

  Future<void> completeSession(String id, {double? qualityScore, String? userInsights}) async {
    final session = _box.get(id);
    if (session == null) return;
    session.completedAt = DateTime.now();
    if (qualityScore != null) session.qualityScore = qualityScore;
    if (userInsights != null) session.userInsights = userInsights;
    await session.save();
  }

  Future<void> deleteSession(String id) async => _box.delete(id);
}
