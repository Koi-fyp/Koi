import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// The microphone, as the call screen needs it. Tests use a fake.
abstract class MicRecorder {
  /// Whether RECORD_AUDIO is granted; shows the Android dialog when it can.
  Future<bool> hasPermission();

  /// Starts recording [MicRecorder.format] into the file at [path].
  Future<void> start(String path);

  /// Stops and returns the file path (null when nothing was recorded).
  Future<String?> stop();

  /// Stops and discards the recording.
  Future<void> cancel();

  Future<void> dispose();

  /// Ahmad, 2026-10-18: only WAV is verified; 16 kHz mono PCM.
  static const int sampleRate = 16000;
  static const int channels = 1;

  /// For the diagnostics line.
  static const String format = 'wav/16kHz/mono';
}

/// record 6.0.0 (newest version that resolves with firebase_auth 4.x).
class RecordMicRecorder implements MicRecorder {
  // Created on first use, so opening the call screen touches no plugin.
  AudioRecorder? _recorder;
  AudioRecorder get _r => _recorder ??= AudioRecorder();

  @override
  Future<bool> hasPermission() => _r.hasPermission();

  @override
  Future<void> start(String path) => _r.start(
    const RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: MicRecorder.sampleRate,
      numChannels: MicRecorder.channels,
    ),
    path: path,
  );

  @override
  Future<String?> stop() => _r.stop();

  @override
  Future<void> cancel() => _r.cancel();

  @override
  Future<void> dispose() async => _recorder?.dispose();
}

/// The app's cache folder (path_provider getTemporaryDirectory()); never
/// backed up, and the clip is deleted after each turn anyway.
Future<String> micTempDir() async => (await getTemporaryDirectory()).path;

/// Deletes [path] if it is still there; errors are ignored. Sync: the
/// clip is at most ~1 MB (30 s of 16 kHz mono PCM).
Future<void> deleteClip(String path) async {
  try {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  } catch (_) {}
}
