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
import 'core/koi_cryptography.dart';
import 'core/key_value_store.dart';
import 'core/onboarding_store.dart';
import 'core/sync_queue.dart';
import 'dev/design_gallery.dart';
import 'onboarding/onboarding_service.dart';
import 'theme/koi_theme.dart';

/// Debug-only Design Gallery switch. Never on in profile/release builds.
/// Run with: flutter run --dart-define=KOI_DESIGN_GALLERY=true
const bool showDesignGallery =
    kDebugMode && bool.fromEnvironment('KOI_DESIGN_GALLERY');

// TODO(firebase): Firebase is NOT initialised yet. No google-services.json has
// been provided. Once android/app/google-services.json exists (or
// `flutterfire configure` has been run against the KOI Firebase project), add
// the Google Services Gradle plugin and call
// `await Firebase.initializeApp()` here, after
// `WidgetsFlutterBinding.ensureInitialized()`. Do not hand-write any config.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fonts are bundled in assets/google_fonts/; never download them at runtime
  // (the app must render correctly offline).
  GoogleFonts.config.allowRuntimeFetching = false;
  LicenseRegistry.addLicense(_bundledFontLicenses);
  // Native PBKDF2 + per-session key cache for KoiCryptoService (Prompt 6).
  KoiCryptography.install();

  await Hive.initFlutter();
  // flutter_lib's encrypted boxes (users, messages, ...). Like web's
  // IndexedDB write, a failure here must not block the app: the user-record
  // write in completeOnboarding then fails and is only logged.
  try {
    await HiveManager.init();
  } catch (e) {
    debugPrint('KOI: HiveManager.init failed: $e');
  }
  final onboarding = OnboardingStore(
    await HiveKeyValueStore.open(OnboardingStore.boxName),
  );
  final messages = await HiveMessageStore.open();
  final online = ConnectivityOnlineStatus();
  final syncQueue = PersistentSyncQueue(
    store: await HiveKeyValueStore.open(PersistentSyncQueue.boxName),
    // TODO(firebase): a cloud_firestore writer once Firebase is connected.
    remote: const FirestoreNotConnectedWriter(),
    onlineChanges: online.changes,
  );

  runApp(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWith((ref) => _createAuthService()),
        onboardingStoreProvider.overrideWith((ref) => onboarding),
        onboardingUserWriterProvider.overrideWithValue(
          HiveUserOnboardingWriter(UserRepository()),
        ),
        onlineStatusProvider.overrideWithValue(online),
        messageStoreProvider.overrideWithValue(messages),
        syncQueueProvider.overrideWithValue(syncQueue),
      ],
      child: const KoiApp(),
    ),
  );
}

// TODO(Q1, firebase): replace with the real AuthService (see
// core/auth/auth_service.dart). Release builds have no auth until then.
AuthService _createAuthService() {
  if (!kDebugMode) {
    throw UnsupportedError(
      'No AuthService in release builds yet: waiting on Q1 + Firebase config.',
    );
  }
  final service = DebugLocalAuthService(
    () => HiveKeyValueStore.open(DebugLocalAuthService.boxName),
  );
  service.restoreSession();
  // Forget derived keys when the user signs out.
  service.addListener(() {
    if (service.user == null) CachingPbkdf2.clear();
  });
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
