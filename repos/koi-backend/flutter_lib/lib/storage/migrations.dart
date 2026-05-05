import 'package:hive/hive.dart';
import '../models/hive_user_model.dart';
import 'hive_manager.dart';

class HiveMigrations {
  static const int currentVersion = 1;

  static Future<void> run(int fromVersion) async {
    for (int v = fromVersion; v < currentVersion; v++) {
      switch (v) {
        case 0:
          await _migrateV0toV1();
          break;
      }
    }
  }

  // Example: backfill default stats for users missing them (future schema adds)
  static Future<void> _migrateV0toV1() async {
    final Box<HiveUser> users = HiveManager.users;
    for (final user in users.values) {
      if (user.totalConversations < 0) {
        user.totalConversations = 0;
        await user.save();
      }
    }
  }
}
