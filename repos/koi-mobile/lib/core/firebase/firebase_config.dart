import 'package:firebase_core/firebase_core.dart';

/// Firebase options from dart-defines, so no Firebase file is ever committed
/// and no Gradle plugin is needed (Dart-only initialisation).
///
/// Run with the private, gitignored file:
///   flutter run --debug --dart-define-from-file=firebase.local.json
/// Its keys are listed in firebase.local.example.json; write it from a local
/// lib/firebase_options.dart with tool/write_firebase_local_config.dart.
///
/// Never log these values.
abstract final class FirebaseConfig {
  static const String apiKeyName = 'KOI_FIREBASE_API_KEY';
  static const String appIdName = 'KOI_FIREBASE_APP_ID';
  static const String senderIdName = 'KOI_FIREBASE_MESSAGING_SENDER_ID';
  static const String projectIdName = 'KOI_FIREBASE_PROJECT_ID';
  static const String storageBucketName = 'KOI_FIREBASE_STORAGE_BUCKET';

  /// Shown when a release build has no config.
  static const String missingMessage =
      'KOI: Firebase config missing. Release builds need '
      '--dart-define-from-file=firebase.local.json '
      '(keys: see firebase.local.example.json).';

  /// The options from this build's dart-defines, or null when none are set.
  static FirebaseOptions? fromEnvironment() => fromValues(
    apiKey: const String.fromEnvironment(apiKeyName),
    appId: const String.fromEnvironment(appIdName),
    messagingSenderId: const String.fromEnvironment(senderIdName),
    projectId: const String.fromEnvironment(projectIdName),
    storageBucket: const String.fromEnvironment(storageBucketName),
  );

  /// Null when every value is empty. Throws [StateError] naming the missing
  /// keys (never the values) when only some required ones are set.
  /// storageBucket is optional.
  static FirebaseOptions? fromValues({
    required String apiKey,
    required String appId,
    required String messagingSenderId,
    required String projectId,
    String storageBucket = '',
  }) {
    final required = {
      apiKeyName: apiKey,
      appIdName: appId,
      senderIdName: messagingSenderId,
      projectIdName: projectId,
    };
    final missing = [
      for (final e in required.entries)
        if (e.value.isEmpty) e.key,
    ];
    if (missing.length == required.length && storageBucket.isEmpty) {
      return null;
    }
    if (missing.isNotEmpty) {
      throw StateError(
        'KOI: Firebase config incomplete, missing ${missing.join(', ')}.',
      );
    }
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      storageBucket: storageBucket.isEmpty ? null : storageBucket,
    );
  }
}
