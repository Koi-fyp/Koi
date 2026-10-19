import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_providers.dart' show accountSecretStoreProvider;
import '../chat/backend_warmup.dart';
import '../chat/chat_api.dart';
import '../chat/chat_controller.dart';
import '../chat/chat_session_state.dart';
import '../chat/conversation_service.dart';
import '../chat/message_record.dart';
import '../core/crypto_context.dart';
import '../core/sync_queue.dart';
import '../core/auth/auth_service.dart';
import '../core/onboarding_store.dart';
import '../environment/environment_providers.dart';
import '../onboarding/onboarding_service.dart';
import '../safety/safety_providers.dart';
import '../settings/settings_prefs.dart';
import '../voice/voice_providers.dart' show speechWarmupProvider;

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
    profileQueue: ref.read(profileSyncQueueProvider),
  ),
);

/// Queue for users/{uid} profile merges. Null (no Firestore writes) unless
/// main.dart has a Firebase config.
final profileSyncQueueProvider = Provider<SyncQueue?>((ref) => null);

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

/// The crisis service, used ONLY for its `GET /health` warm-up (same
/// redirect handling as chat). C8 decided 2026-10-18: no client calls
/// POST /api/v1/crisis. Not configured unless KOI_CRISIS_BASE is set.
final crisisHealthClientProvider = Provider<ChatApiClient>(
  (ref) => ChatApiClient(baseUrl: koiCrisisBase),
);

/// exercise_state / client_event / crisis_path for the signed-in user's
/// conversation; a new one for every uid. SafetyController's callbacks feed
/// it.
final chatSessionStateProvider = Provider<ChatSessionState>((ref) {
  ref.watch(authServiceProvider.select((a) => a.user?.uid));
  final session = ChatSessionState();
  ref.read(safetyControllerProvider)
    ..onClientEvent = session.setClientEvent
    ..onCrisisPath = session.setCrisisPath;
  return session;
});

/// `/health` warm-up and the "waking up" status. Created by RootRouter so
/// the warm-up runs as soon as a user is signed in (also from onboarding),
/// and again when the app returns after more than 5 minutes away.
final backendWarmupProvider = ChangeNotifierProvider<BackendWarmup>((ref) {
  final chat = ref.read(chatApiProvider);
  final crisis = ref.read(crisisHealthClientProvider);
  final warmup = BackendWarmup(
    chatHealth: chat.isConfigured ? chat.checkHealth : null,
    crisisHealth: crisis.isConfigured ? crisis.checkHealth : null,
    speechSettled: ref.read(speechWarmupProvider).settled,
  );
  ref.listen(authServiceProvider.select((a) => a.user?.uid), (prev, uid) {
    if (uid != null && uid != prev) warmup.warmUp();
  }, fireImmediately: true);
  final lifecycle = AppLifecycleListener(
    onHide: warmup.appBackgrounded,
    onShow: warmup.appResumed,
  );
  ref.onDispose(lifecycle.dispose);
  return warmup;
});

final messageCipherProvider = Provider<MessageCipher>(
  (ref) => KoiMessageCipher(),
);

/// Without Firebase (debug builds without the config): every Firestore call
/// fails, so anonymous users generate and cache a salt locally and queue the
/// create-once; linked users are blocked. main.dart overrides this with the
/// Firestore-backed resolver when Firebase is configured.
final cryptoContextResolverProvider = Provider<CryptoContextResolver>(
  (ref) => CryptoContextResolver(
    anonymousSecret: ref.read(accountSecretStoreProvider).anonymousSecret,
    fetchSalt: (uid) async => throw StateError('Firestore is not connected'),
    createSaltOnce: (uid, candidate) async =>
        throw StateError('Firestore is not connected'),
    isOnline: () => ref.read(onlineStatusProvider).check(),
    syncQueue: ref.read(syncQueueProvider),
  ),
);

/// Q4: the correct two-argument form. MOB-1: a linked user's secret is
/// the account password cached per uid (koi_linked_secret_{uid}); the root
/// shows the unlock screen until it is there.
final cryptoContextGetterProvider = Provider<CryptoContextGetter>(
  (ref) => (uid) async {
    final linked = ref.read(authServiceProvider).isLinked;
    return ref
        .read(cryptoContextResolverProvider)
        .getActiveCryptoContext(
          uid,
          AuthState(
            isLinked: linked,
            linkedSecret: linked
                ? await ref.read(accountSecretStoreProvider).linkedSecret(uid)
                : null,
          ),
        );
  },
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
        safety: ref.read(safetyControllerProvider),
        session: ref.read(chatSessionStateProvider),
        backend: ref.read(backendWarmupProvider),
      );
      controller.loadHistory().then((_) => controller.warmUpKey());
      // Background tint (Prompt 27). Not cancelled: the stream closes when
      // the controller is disposed.
      controller.avatarEvents.listen(
        ref.read(environmentControllerProvider).onAvatarEvent,
      );
      return controller;
    });

// ── Settings (Prompt 7) ─────────────────────────────────────────────────────

/// Overridden in main.dart (flutter_lib UserRepository) and in tests.
final settingsPrefsStoreProvider = Provider<SettingsPrefsStore>(
  (ref) =>
      throw UnimplementedError('settingsPrefsStoreProvider must be overridden'),
);
