import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app/providers.dart';
import 'app/root_router.dart';
import 'core/auth/auth_service.dart';
import 'core/auth/debug_local_auth_service.dart';
import 'core/key_value_store.dart';
import 'core/onboarding_store.dart';
import 'dev/design_gallery.dart';
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

  await Hive.initFlutter();
  final onboarding = OnboardingStore(
    await HiveKeyValueStore.open(OnboardingStore.boxName),
  );

  runApp(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWith((ref) => _createAuthService()),
        onboardingStoreProvider.overrideWith((ref) => onboarding),
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
