import 'package:hive/hive.dart';
import '../hive_manager.dart';
import '../../models/hive_message_model.dart';

class MessageRepository {
  Box<HiveMessage> get _box => HiveManager.messages;

  Future<void> saveMessage(HiveMessage message) async =>
      _box.put(message.id, message);

  Future<void> saveMessages(List<HiveMessage> messages) async {
    final map = {for (final m in messages) m.id: m};
    await _box.putAll(map);
  }

  HiveMessage? getMessage(String id) => _box.get(id);

  List<HiveMessage> getByConversation(String conversationId) {
    return _box.values
        .where((m) => m.conversationId == conversationId)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  List<HiveMessage> getUnsynced() =>
      _box.values.where((m) => !m.synced).toList();

  Future<void> markSynced(String id) async {
    final message = _box.get(id);
    if (message == null) return;
    message.synced = true;
    await message.save();
  }

  Future<void> markAllSynced(List<String> ids) async {
    for (final id in ids) {
      await markSynced(id);
    }
  }

  Future<void> deleteMessage(String id) async => _box.delete(id);

  Future<void> deleteConversation(String conversationId) async {
    final keys = _box.values
        .where((m) => m.conversationId == conversationId)
        .map((m) => m.id)
        .toList();
    await _box.deleteAll(keys);
  }
}
