import 'package:hive/hive.dart';
import '../hive_manager.dart';
import '../../models/hive_task_model.dart';

class TaskRepository {
  Box<HiveTask> get _box => HiveManager.tasks;

  Future<void> saveTask(HiveTask task) async => _box.put(task.id, task);

  HiveTask? getTask(String id) => _box.get(id);

  List<HiveTask> getActiveByUser(String userId) {
    return _box.values
        .where((t) => t.userId == userId && !t.archived)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  List<HiveTask> getCompletedByUser(String userId) {
    return _box.values
        .where((t) => t.userId == userId && t.completedAt != null)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  List<HiveTask> getUnsynced() =>
      _box.values.where((t) => !t.synced).toList();

  Future<void> markSynced(String id) async {
    final task = _box.get(id);
    if (task == null) return;
    task.synced = true;
    await task.save();
  }

  Future<void> completeTask(String id) async {
    final task = _box.get(id);
    if (task == null) return;
    task.completedAt = DateTime.now();
    await task.save();
  }

  Future<void> archiveTask(String id) async {
    final task = _box.get(id);
    if (task == null) return;
    task.archived = true;
    await task.save();
  }

  Future<void> deleteTask(String id) async => _box.delete(id);
}
