import 'package:hive/hive.dart';
import '../hive_manager.dart';
import '../../models/hive_user_model.dart';

class UserRepository {
  Box<HiveUser> get _box => HiveManager.users;

  Future<HiveUser?> getUser(String id) async => _box.get(id);

  Future<void> saveUser(HiveUser user) async => _box.put(user.id, user);

  Future<void> updateLastActive(String id) async {
    final user = _box.get(id);
    if (user == null) return;
    user.lastActive = DateTime.now();
    await user.save();
  }

  Future<void> deleteUser(String id) async => _box.delete(id);

  List<HiveUser> getAllUsers() => _box.values.toList();

  bool hasUser(String id) => _box.containsKey(id);
}
