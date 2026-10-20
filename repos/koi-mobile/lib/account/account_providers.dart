import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../checkins/checkin_providers.dart';
import '../core/crypto_context.dart';
import '../core/key_value_store.dart';
import '../core/sync_queue.dart';
import '../experts/expert_api.dart';
import '../platform/platform_client.dart';
import '../platform/platform_config.dart';
import '../safety_plan/safety_plan_providers.dart';
import 'account_controller.dart';
import 'account_migration.dart';
import 'capabilities.dart';
import 'capability_controller.dart';
import 'secret_store.dart';

/// Per-uid CSE secrets. main.dart passes the same instance to the crypto
/// context resolver; tests override it with a [MemorySecureKv].
final accountSecretStoreProvider = Provider<AccountSecretStore>(
  (ref) => AccountSecretStore(const FlutterSecureKv()),
);

/// The plain `koi_local_prefs` box (migration markers). Overridden in
/// main.dart.
final localPrefsProvider = Provider<KeyValueStore>(
  (ref) => MemoryKeyValueStore(),
);

/// True when main.dart has a Firebase config. Without it (debug stand-in),
/// a registered account's salt may be generated locally and queued, since
/// no server can ever hold one.
final firebaseConfiguredProvider = Provider<bool>((ref) => false);

final accountCleanupProvider = Provider<AccountCleanup>(
  (ref) => AccountCleanup(),
);

/// Authenticated client for the KOI 2.0 platform API (KOI_PLATFORM_BASE).
final platformClientProvider = Provider<PlatformClient>((ref) {
  final auth = ref.read(authServiceProvider);
  return PlatformClient(
    base: platformBaseUri(),
    transport: DioPlatformTransport(),
    idToken: auth.getIdToken,
    refreshIdToken: auth.refreshIdToken,
  );
});

/// Mock (KOI_MOCKS) > real (KOI_PLATFORM_BASE) > unavailable (default-deny).
final capabilitiesSourceProvider = Provider<CapabilitiesSource>((ref) {
  if (koiMocksEnabled) return MockCapabilitiesSource();
  final client = ref.read(platformClientProvider);
  return client.isConfigured
      ? HttpCapabilitiesSource(client)
      : const UnavailableCapabilitiesSource();
});

final capabilityControllerProvider =
    ChangeNotifierProvider<CapabilityController>((ref) {
      final cleanup = ref.read(accountCleanupProvider);
      final controller = CapabilityController(
        auth: ref.read(authServiceProvider),
        source: ref.read(capabilitiesSourceProvider),
        onPatientAccessLost: cleanup.patientAccessLost,
      );
      // Any 403 from the platform re-checks the capabilities.
      ref.read(platformClientProvider).onForbidden = controller.onForbidden;
      final lifecycle = AppLifecycleListener(onResume: controller.appResumed);
      ref.onDispose(lifecycle.dispose);
      return controller;
    });

/// The confirmed capabilities of the CURRENT uid, or none (default-deny).
final effectiveCapabilitiesProvider = Provider<KoiCapabilities>(
  (ref) => ref.watch(capabilityControllerProvider).effective,
);

final expertDirectoryApiProvider = Provider<ExpertDirectoryApi>((ref) {
  if (koiMocksEnabled) return MockExpertDirectoryApi();
  final client = ref.read(platformClientProvider);
  return client.isConfigured
      ? HttpExpertDirectoryApi(client)
      : const UnavailableExpertDirectoryApi();
});

/// Uploads with acknowledgement (the persistent queue), or a queue that
/// can never acknowledge (tests / no queue): then nothing is ever deleted.
final migrationUploaderProvider = Provider<MigrationUploader>((ref) {
  final queue = ref.read(syncQueueProvider);
  return queue is PersistentSyncQueue
      ? SyncQueueMigrationUploader(queue)
      : _NoAckUploader(queue);
});

class _NoAckUploader implements MigrationUploader {
  _NoAckUploader(this.queue);
  final SyncQueue queue;

  @override
  Future<bool> writeNow(SyncItem item) async {
    queue.enqueue(item);
    return false;
  }

  @override
  Future<int> removeWhere(bool Function(SyncItem item) test) async => 0;
}

final cseMigrationProvider = Provider<CseMigration>(
  (ref) => CseMigration(
    messages: ref.read(messageStoreProvider),
    checkIns: ref.read(checkInBoxProvider),
    safetyPlans: ref.read(safetyPlanBoxProvider),
    cipher: ref.read(messageCipherProvider),
    uploader: ref.read(migrationUploaderProvider),
    markers: ref.read(localPrefsProvider),
  ),
);

final accountControllerProvider = ChangeNotifierProvider<AccountController>((
  ref,
) {
  final resolver = ref.read(cryptoContextResolverProvider);
  final queueSalt = !ref.read(firebaseConfiguredProvider);
  return AccountController(
    auth: ref.read(authServiceProvider),
    secrets: ref.read(accountSecretStoreProvider),
    migration: ref.read(cseMigrationProvider),
    resolveContext: (uid, {linkedSecret}) => resolver.getActiveCryptoContext(
      uid,
      AuthState(isLinked: linkedSecret != null, linkedSecret: linkedSecret),
    ),
    ensureSalt: (uid) =>
        resolver.ensureSaltCreated(uid, queueOnFailure: queueSalt),
    onboarding: ref.read(onboardingStoreProvider),
    messages: ref.read(messageStoreProvider),
    cipher: ref.read(messageCipherProvider),
    prefs: ref.read(localPrefsProvider),
    cleanup: ref.read(accountCleanupProvider),
  );
});
