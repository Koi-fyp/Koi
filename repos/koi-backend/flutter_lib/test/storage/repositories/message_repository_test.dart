import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:koi_flutter_lib/models/hive_message_model.dart';
import 'package:koi_flutter_lib/storage/hive_manager.dart';
import 'package:koi_flutter_lib/storage/repositories/message_repository.dart';

HiveMessage makeMessage(String id, String convId, {bool synced = false}) =>
    HiveMessage(
      id: id,
      conversationId: convId,
      sender: 'user',
      content: 'hello',
      timestamp: DateTime(2024, 1, 1, 12, 0),
      synced: synced,
    );

void main() {
  late Directory tempDir;
  late MessageRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(HiveMessageAdapter());
    await Hive.openBox<HiveMessage>(HiveManager.messagesBox);
    repo = MessageRepository();
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  test('saveMessage and getMessage round-trip', () async {
    final msg = makeMessage('m1', 'conv1');
    await repo.saveMessage(msg);
    final found = repo.getMessage('m1');
    expect(found, isNotNull);
    expect(found!.content, equals('hello'));
  });

  test('getByConversation returns sorted messages', () async {
    await repo.saveMessage(HiveMessage(
      id: 'm2', conversationId: 'conv2', sender: 'user',
      content: 'second', timestamp: DateTime(2024, 1, 1, 13), synced: false));
    await repo.saveMessage(HiveMessage(
      id: 'm1', conversationId: 'conv2', sender: 'ai',
      content: 'first', timestamp: DateTime(2024, 1, 1, 12), synced: false));
    final msgs = repo.getByConversation('conv2');
    expect(msgs.length, equals(2));
    expect(msgs[0].content, equals('first'));
    expect(msgs[1].content, equals('second'));
  });

  test('getUnsynced returns only unsynced', () async {
    await repo.saveMessage(makeMessage('m3', 'conv3', synced: false));
    await repo.saveMessage(makeMessage('m4', 'conv3', synced: true));
    final unsynced = repo.getUnsynced();
    expect(unsynced.length, equals(1));
    expect(unsynced[0].id, equals('m3'));
  });

  test('markSynced updates synced flag', () async {
    await repo.saveMessage(makeMessage('m5', 'conv4', synced: false));
    await repo.markSynced('m5');
    expect(repo.getMessage('m5')!.synced, isTrue);
  });

  test('deleteConversation removes all messages', () async {
    await repo.saveMessage(makeMessage('m6', 'conv5'));
    await repo.saveMessage(makeMessage('m7', 'conv5'));
    await repo.deleteConversation('conv5');
    expect(repo.getByConversation('conv5'), isEmpty);
  });
}
