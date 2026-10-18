import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/chat/chat_api.dart';
import 'package:koi_mobile/chat/chat_controller.dart';
import 'package:koi_mobile/chat/conversation_service.dart';
import 'package:koi_mobile/chat/message_record.dart';
import 'package:koi_mobile/environment/environment_controller.dart';
import 'package:koi_mobile/environment/environment_palette.dart';

import '../support/chat_fakes.dart';
import '../support/fake_chat_server.dart';

// Plain test() only: a widget test in the same file would make every
// HttpClient request return 400.
void main() {
  group('ATC-M6-07 chat stream (127.0.0.1)', () {
    late FakeChatServer server;
    setUp(() async => server = await FakeChatServer.start());
    tearDown(() => server.close());

    test('companion_state from a real turn reaches the controller', () async {
      server.handler = (req, _) => writeSse(req, okTurn());
      final chat = ChatController(
        uid: 'u1',
        service: ConversationService(
          cryptoContext: (_) async => testCryptoContext,
          cipher: FakeCipher(),
          store: MemoryMessageStore(),
          syncQueue: RecordingSyncQueue(),
          api: ChatApiClient(baseUrl: server.base),
          idToken: () async => 'fake-test-token',
        ),
        isOnline: () async => true,
      );
      final env = EnvironmentController(uid: 'u1');
      chat.avatarEvents.listen(env.onAvatarEvent);
      await chat.send('hi');
      await pumpEventQueue();
      expect(env.mood, EnvironmentMood.joy);
      chat.dispose();
    });
  });
}
