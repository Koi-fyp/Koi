// Writes the gitignored firebase.local.json from a local, gitignored
// lib/firebase_options.dart (the `android` FirebaseOptions block).
//
// Run from repos/koi-mobile:
//   dart run tool/write_firebase_local_config.dart
//
// It never prints a value: only the key names it wrote. It refuses to run
// unless git confirms firebase.local.json is ignored.

import 'dart:convert';
import 'dart:io';

const _source = 'lib/firebase_options.dart';
const _target = 'firebase.local.json';

/// firebase_options.dart field → dart-define name (firebase_config.dart).
const _names = {
  'apiKey': 'KOI_FIREBASE_API_KEY',
  'appId': 'KOI_FIREBASE_APP_ID',
  'messagingSenderId': 'KOI_FIREBASE_MESSAGING_SENDER_ID',
  'projectId': 'KOI_FIREBASE_PROJECT_ID',
  'storageBucket': 'KOI_FIREBASE_STORAGE_BUCKET',
};
const _required = ['apiKey', 'appId', 'messagingSenderId', 'projectId'];

Never _fail(String message) {
  stderr.writeln('write_firebase_local_config: $message');
  exit(1);
}

void main() {
  final ignored = Process.runSync('git', ['check-ignore', '-q', _target]);
  if (ignored.exitCode != 0) {
    _fail('$_target is not gitignored here; refusing to write it.');
  }

  final source = File(_source);
  if (!source.existsSync()) _fail('$_source not found.');
  final text = source.readAsStringSync();

  final block = RegExp(
    r'static\s+const\s+FirebaseOptions\s+android\s*=\s*FirebaseOptions\(([\s\S]*?)\);',
  ).firstMatch(text);
  if (block == null) _fail('no `android` FirebaseOptions in $_source.');

  final fields = {
    for (final m in RegExp(
      r"(\w+)\s*:\s*'([^']*)'",
    ).allMatches(block.group(1)!))
      m.group(1)!: m.group(2)!,
  };
  final missing = [
    for (final k in _required)
      if ((fields[k] ?? '').isEmpty) k,
  ];
  if (missing.isNotEmpty) _fail('missing ${missing.join(', ')} in $_source.');

  final out = {
    for (final e in _names.entries)
      if ((fields[e.key] ?? '').isNotEmpty) e.value: fields[e.key],
  };
  File(
    _target,
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(out)}\n');
  stdout.writeln('Wrote $_target with keys: ${out.keys.join(', ')}');
}
