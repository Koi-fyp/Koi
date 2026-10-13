import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/chat_api.dart';
import '../chat/chat_controller.dart';
import '../chat/conversation_service.dart';
import '../chat/message_record.dart';
import '../core/crypto_context.dart';
import '../core/sync_queue.dart';
import '../core/auth/auth_service.dart';
import '../core/onboarding_store.dart';
import '../onboarding/onboarding_service.dart';
import '../settings/settings_prefs.dart';

/// Overridden in main.dart (and in tests) with a concrete implementation.
final authServiceProvider = ChangeNotifierProvider<AuthService>(
  (ref) => throw UnimplementedError('authServiceProvider must be overridden'),
);

/// Overridden in main.dart (and in tests) with the opened Hive box.
final onboardingStoreProvider = ChangeNotifierProvider<OnboardingStore>(
  (ref) =>
      throw UnimplementedError('onboardingStoreProvider must be overridden'),
);

/// Overridden in main.dart (flutter_lib UserRepository) and in tests.
final onboardingUserWriterProvider = Provider<OnboardingUserWriter>(
  (ref) => throw UnimplementedError(
    'onboardingUserWriterProvider must be overridden',
  ),
);

final onboardingServiceProvider = Provider<OnboardingService>(
  (ref) => OnboardingService(
    flag: ref.read(onboardingStoreProvider),
    users: ref.read(onboardingUserWriterProvider),
    currentUid: () => ref.read(authServiceProvider).user?.uid,
  ),
);

// ── Chat (Prompt 6) ─────────────────────────────────────────────────────────

/// Device connectivity (web: navigator.onLine + online/offline events).
/// Overridden in tests.
abstract class OnlineStatus {
  Future<bool> check();
  Stream<bool> get changes;
}

class ConnectivityOnlineStatus implements OnlineStatus {
  ConnectivityOnlineStatus([Connectivity? c]) : _c = c ?? Connectivity();
  final Connectivity _c;

  @override
  Future<bool> check() async => isOnlineFrom(await _c.checkConnectivity());

  @override
  Stream<bool> get changes => _c.onConnectivityChanged.map(isOnlineFrom);
}

final onlineStatusProvider = Provider<OnlineStatus>(
  (ref) => ConnectivityOnlineStatus(),
);

/// Current online state: initial check, then every change.
final onlineProvider = StreamProvider<bool>((ref) async* {
  final status = ref.watch(onlineStatusProvider);
  yield await status.check();
  yield* status.changes;
});

/// Overridden in main.dart (Hive box) and in tests.
final messageStoreProvider = Provider<MessageStore>(
  (ref) => throw UnimplementedError('messageStoreProvider must be overridden'),
);

/// Overridden in main.dart (persistent queue) and in tests.
final syncQueueProvider = Provider<SyncQueue>(
  (ref) => throw UnimplementedError('syncQueueProvider must be overridden'),
);

final chatApiProvider = Provider<ChatApiClient>(
  (ref) => ChatApiClient(baseUrl: koiApiBase),
);

final messageCipherProvider = Provider<MessageCipher>(
  (ref) => KoiMessageCipher(),
);

final cryptoContextResolverProvider = Provider<CryptoContextResolver>(
  (ref) => CryptoContextResolver(
    // TODO(firebase): read users/{uid}.public_crypto_metadata.salt from
    // Firestore. Until then the fetch fails; anonymous users then generate
    // and cache a salt locally (crypto.ts fallback), linked users are blocked.
    fetchSalt: (uid) async =>
        throw StateError('Firestore is not connected yet'),
    isOnline: () => ref.read(onlineStatusProvider).check(),
    syncQueue: ref.read(syncQueueProvider),
  ),
);

/// Q4: the correct two-argument form. Linked users would also need their
/// password here; there is no unlock step yet (AuthContext.tsx header).
final cryptoContextGetterProvider = Provider<CryptoContextGetter>(
  (ref) =>
      (uid) => ref
          .read(cryptoContextResolverProvider)
          .getActiveCryptoContext(
            uid,
            AuthState(isLinked: ref.read(authServiceProvider).isLinked),
          ),
);

final conversationServiceProvider = Provider<ConversationService>((ref) {
  final auth = ref.read(authServiceProvider);
  return ConversationService(
    cryptoContext: ref.read(cryptoContextGetterProvider),
    cipher: ref.read(messageCipherProvider),
    store: ref.read(messageStoreProvider),
    syncQueue: ref.read(syncQueueProvider),
    api: ref.read(chatApiProvider),
    idToken: auth.getIdToken,
  );
});

/// One chat per signed-in uid (Q5: conversationId = uid).
final chatControllerProvider = ChangeNotifierProvider.autoDispose
    .family<ChatController, String>((ref, uid) {
      final online = ref.read(onlineStatusProvider);
      final controller = ChatController(
        uid: uid,
        service: ref.read(conversationServiceProvider),
        isOnline: online.check,
        onlineChanges: online.changes,
      );
      controller.loadHistory().then((_) => controller.warmUpKey());
      return controller;
    });

// ── Settings (Prompt 7) ─────────────────────────────────────────────────────

/// Overridden in main.dart (flutter_lib UserRepository) and in tests.
final settingsPrefsStoreProvider = Provider<SettingsPrefsStore>(
  (ref) =>
      throw UnimplementedError('settingsPrefsStoreProvider must be overridden'),
);
