import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/hive_user_model.dart';
import '../models/hive_message_model.dart';
import '../models/hive_mood_entry_model.dart';
import '../models/hive_cbt_session_model.dart';
import '../models/hive_task_model.dart';

class HiveManager {
  static const String _encryptionKeyStorageKey = 'hive_encryption_key';

  // Box name constants
  static const String usersBox = 'users';
  static const String messagesBox = 'messages';
  static const String moodEntriesBox = 'mood_entries';
  static const String cbtSessionsBox = 'cbt_sessions';
  static const String tasksBox = 'tasks';

  static Future<void> init() async {
    await Hive.initFlutter();

    final encryptionKey = await _getOrCreateEncryptionKey();
    final cipher = HiveAesCipher(encryptionKey);

    // Register adapters (check isAdapterRegistered first)
    _registerAdapters();

    // Open all boxes with encryption
    await Future.wait([
      Hive.openBox<HiveUser>(usersBox, encryptionCipher: cipher),
      Hive.openBox<HiveMessage>(messagesBox, encryptionCipher: cipher),
      Hive.openBox<HiveMoodEntry>(moodEntriesBox, encryptionCipher: cipher),
      Hive.openBox<HiveCBTSession>(cbtSessionsBox, encryptionCipher: cipher),
      Hive.openBox<HiveTask>(tasksBox, encryptionCipher: cipher),
    ]);
  }

  static void _registerAdapters() {
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(HiveUserAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(HiveMessageAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(HiveMoodEntryAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(HiveCBTSessionAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(HiveTaskAdapter());
  }

  static Future<List<int>> _getOrCreateEncryptionKey() async {
    const storage = FlutterSecureStorage();
    String? keyString = await storage.read(key: _encryptionKeyStorageKey);

    if (keyString == null) {
      final key = Hive.generateSecureKey();
      keyString = base64UrlEncode(key);
      await storage.write(key: _encryptionKeyStorageKey, value: keyString);
      return key;
    }

    return base64Url.decode(keyString);
  }

  // Typed box accessors
  static Box<HiveUser> get users => Hive.box<HiveUser>(usersBox);
  static Box<HiveMessage> get messages => Hive.box<HiveMessage>(messagesBox);
  static Box<HiveMoodEntry> get moodEntries => Hive.box<HiveMoodEntry>(moodEntriesBox);
  static Box<HiveCBTSession> get cbtSessions => Hive.box<HiveCBTSession>(cbtSessionsBox);
  static Box<HiveTask> get tasks => Hive.box<HiveTask>(tasksBox);

  static Future<void> closeAll() async {
    await Hive.close();
  }

  static Future<void> clearAll() async {
    await Future.wait([
      users.clear(),
      messages.clear(),
      moodEntries.clear(),
      cbtSessions.clear(),
      tasks.clear(),
    ]);
  }
}
