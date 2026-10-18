import 'dart:io';

import 'package:koi_mobile/voice_input/mic_recorder.dart';

/// Writes a small fake WAV on start, like the real recorder writes a file;
/// cancel deletes it (record's cancel() removes the file too).
class FakeMicRecorder implements MicRecorder {
  bool granted = true;
  int permissionAsks = 0;
  final List<String> started = [];
  int stops = 0;
  int cancels = 0;
  bool disposed = false;

  /// Order of calls across fakes (e.g. voice stop before start).
  List<String>? log;

  String? get current => started.isEmpty ? null : started.last;

  @override
  Future<bool> hasPermission() async {
    permissionAsks++;
    return granted;
  }

  @override
  Future<void> start(String path) async {
    log?.add('record');
    started.add(path);
    File(path).writeAsStringSync('RIFF-fake-wav');
  }

  @override
  Future<String?> stop() async {
    stops++;
    return current;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    final p = current;
    if (p != null && File(p).existsSync()) File(p).deleteSync();
  }

  @override
  Future<void> dispose() async => disposed = true;
}
