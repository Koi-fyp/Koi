import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/key_value_store.dart';
import 'mic_controller.dart';
import 'mic_recorder.dart';

/// Overridden in main.dart with the `koi_local_prefs` box; in memory
/// otherwise (tests).
final micPrefsProvider = Provider<MicPrefs>(
  (ref) => MicPrefs(MemoryKeyValueStore()),
);

/// The platform microphone; tests override it.
final micRecorderFactoryProvider = Provider<MicRecorder Function()>(
  (ref) => RecordMicRecorder.new,
);

/// Where clips are written (the app's cache folder); tests override it.
final micTempDirProvider = Provider<Future<String> Function()>(
  (ref) => micTempDir,
);

/// The last voice message's diagnostics line (debug menu).
final micDiagnosticsProvider = Provider<MicDiagnosticsLog>(
  (ref) => MicDiagnosticsLog(),
);

/// The recording timer's clock; widget tests use the test binding's clock.
final micClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
