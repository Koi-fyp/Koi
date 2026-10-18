import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:koi_flutter_lib/storage/hive_manager.dart';
import 'package:koi_flutter_lib/storage/repositories/user_repository.dart';

import 'app/providers.dart';
import 'app/root_router.dart';
import 'chat/message_record.dart';
import 'core/auth/auth_service.dart';
import 'core/auth/debug_local_auth_service.dart';
import 'core/auth/firebase_auth_service.dart';
import 'core/crypto_context.dart';
import 'core/firebase/firebase_config.dart';
import 'core/firebase/firebase_session.dart';
import 'core/firestore/firestore_remote_writer.dart';
import 'core/firestore/profile_sync.dart';
import 'core/firestore/user_document_store.dart';
import 'core/koi_cryptography.dart';
import 'core/key_value_store.dart';
import 'core/onboarding_store.dart';
import 'core/sync_queue.dart';
import 'dev/design_gallery.dart';
import 'modes/input_mode.dart';
import 'onboarding/onboarding_service.dart';
import 'settings/settings_prefs.dart';
import 'theme/koi_theme.dart';
import 'voice_input/mic_controller.dart';
import 'voice_input/mic_providers.dart';

/// Debug-only Design Gallery switch. Never on in profile/release builds.
/// Run with: flutter run --dart-define=KOI_DESIGN_GALLERY=true
const bool showDesignGallery =
    kDebugMode && bool.fromEnvironment('KOI_DESIGN_GALLERY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fonts are bundled in assets/google_fonts/; never download them at runtime
  // (the app must render correctly offline).
  GoogleFonts.config.allowRuntimeFetching = false;
  LicenseRegistry.addLicense(_bundledFontLicenses);
  // Native PBKDF2 + per-session key cache for KoiCryptoService (Prompt 6).
  KoiCryptography.install();

  // Firebase options come from the gitignored firebase.local.json
  // (--dart-define-from-file); see core/firebase/firebase_config.dart.
  // Without them, debug builds run on the debug stand-in; release builds
  // stop here with a clear message.
  final firebaseOptions = FirebaseConfig.fromEnvironment();
  if (firebaseOptions == null && !kDebugMode) {
    throw StateError(FirebaseConfig.missingMessage);
  }
  FirebaseFirestore? firestore;
  if (firebaseOptions != null) {
    await Firebase.initializeApp(options: firebaseOptions);
    firestore = FirebaseFirestore.instance
      // No Firestore offline cache: the sync queue is the only retry path,
      // and every call times out (firestoreTimeout) instead of waiting for
      // the server forever.
      ..settings = const Settings(persistenceEnabled: false);
  }

  await Hive.initFlutter();
  // flutter_lib's encrypted boxes (users, messages, ...). Like web's
  // IndexedDB write, a failure here must not block the app: the user-record
  // write in completeOnboarding then fails and is only logged.
  try {
    await HiveManager.init();
  } catch (e) {
    debugPrint('KOI: HiveManager.init failed: $e');
  }
  final localPrefs = await HiveKeyValueStore.open(OnboardingStore.boxName);
  final onboarding = OnboardingStore(localPrefs);
  // The old per-device onboarding flag belongs to the persisted debug uid,
  // if any; every other uid goes through onboarding.
  await onboarding.migrateDeviceFlag(
    (await HiveKeyValueStore.open(DebugLocalAuthService.boxName))
        .get(DebugLocalAuthService.uidKey),
  );
  final messages = await HiveMessageStore.open();
  final online = ConnectivityOnlineStatus();

  final auth = firestore != null
      ? FirebaseAuthService(FirebaseAuthBackend())
      : _createDebugAuthService();
  // Forget derived keys when the user signs out.
  auth.addListener(() {
    if (auth.user == null) CachingPbkdf2.clear();
  });

  final saltCache = SaltCache();
  final userDocs = firestore == null ? null : UserDocumentStore(firestore);
  final syncQueue = PersistentSyncQueue(
    store: await HiveKeyValueStore.open(PersistentSyncQueue.boxName),
    remote: firestore == null || userDocs == null
        ? const FirestoreNotConnectedWriter()
        : FirestoreRemoteWriter(
            firestore: firestore,
            currentUid: () => auth.user?.uid,
            userDocs: userDocs,
            saltCache: saltCache,
          ),
    onlineChanges: online.changes,
  );
  SettingsPrefsStore settings = HiveUserSettingsStore(UserRepository());

  final firebaseOverrides = <Override>[];
  if (userDocs != null) {
    final resolver = CryptoContextResolver(
      fetchSalt: userDocs.fetchSalt,
      createSaltOnce: userDocs.createSaltOnce,
      isOnline: online.check,
      syncQueue: syncQueue,
      saltCache: saltCache,
    );
    final session = FirebaseSessionSync(
      ensureUserDocument: userDocs.ensureCreated,
      ensureSalt: (uid) =>
          resolver.ensureSaltStored(uid, AuthState(isLinked: auth.isLinked)),
      isOnline: online.check,
      flush: syncQueue.flush,
      onlineChanges: online.changes,
    );
    auth.addListener(() => session.userChanged(auth.user?.uid));
    settings = SyncingSettingsPrefsStore(settings, syncQueue);
    firebaseOverrides.addAll([
      cryptoContextResolverProvider.overrideWithValue(resolver),
      profileSyncQueueProvider.overrideWithValue(syncQueue),
    ]);
  }

  runApp(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWith((ref) => auth),
        onboardingStoreProvider.overrideWith((ref) => onboarding),
        modePrefsProvider.overrideWithValue(ModePrefs(localPrefs)),
        micPrefsProvider.overrideWithValue(MicPrefs(localPrefs)),
        onboardingUserWriterProvider.overrideWithValue(
          HiveUserOnboardingWriter(UserRepository()),
        ),
        settingsPrefsStoreProvider.overrideWithValue(settings),
        onlineStatusProvider.overrideWithValue(online),
        messageStoreProvider.overrideWithValue(messages),
        syncQueueProvider.overrideWithValue(syncQueue),
        ...firebaseOverrides,
      ],
      child: const KoiApp(),
    ),
  );
}

/// Debug builds without the Firebase config only (main() stops release
/// builds without it first).
AuthService _createDebugAuthService() {
  final service = DebugLocalAuthService(
    () => HiveKeyValueStore.open(DebugLocalAuthService.boxName),
  );
  service.restoreSession();
  return service;
}

/// Registers the OFL licenses of the bundled fonts with Flutter's license page.
Stream<LicenseEntry> _bundledFontLicenses() async* {
  for (final (package, file) in const [
    ('Bricolage Grotesque', 'OFL-BricolageGrotesque.txt'),
    ('DM Sans', 'OFL-DMSans.txt'),
  ]) {
    final text = await rootBundle.loadString('assets/google_fonts/$file');
    yield LicenseEntryWithLineBreaks([package], text);
  }
}

class KoiApp extends StatelessWidget {
  const KoiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KOI — Your AI Companion', // src/app/layout.tsx metadata.title
      debugShowCheckedModeBanner: false,
      theme: KoiTheme.light(),
      home: showDesignGallery ? const DesignGallery() : const RootRouter(),
    );
  }
}
