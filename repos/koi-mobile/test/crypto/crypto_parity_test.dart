// Crypto parity PRE-CHECK (playbook Prompt 3, Part A).
//
// Checks that flutter_lib's KoiCryptoService (Dart) and the web crypto.ts
// logic (reproduced in tool/web_crypto_parity.mjs) read each other's payloads:
//   web → Dart: test/fixtures/web_crypto_vectors.json (made by the Node tool)
//   Dart → web: payloads encrypted here are decrypted by the Node tool
//
// This does NOT close Gate 1-J. Gate 1-J is a joint live test with real
// Firestore data in both directions, scheduled with the team.
//
// Requires Node (>= 20) on PATH for the Dart → web direction.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koi_flutter_lib/services/crypto_service.dart';

const _fixturePath = 'test/fixtures/web_crypto_vectors.json';
const _tool = 'tool/web_crypto_parity.mjs';

// 600,000 PBKDF2 iterations run in pure Dart here; give each case room.
const _slow = Timeout(Duration(minutes: 3));

List<Map<String, dynamic>> _loadCases() {
  final doc = jsonDecode(File(_fixturePath).readAsStringSync())
      as Map<String, dynamic>;
  return (doc['cases'] as List).cast<Map<String, dynamic>>();
}

/// Structural checks shared by web and Dart payloads (crypto.ts format:
/// v1:PBKDF2:salt:nonce(12 bytes):ciphertext + 16-byte GCM tag).
void _expectFormat(String payload, String salt, String plaintext) {
  final parts = payload.split(':');
  expect(parts, hasLength(5));
  expect(parts[0], 'v1');
  expect(parts[1], 'PBKDF2');
  expect(parts[2], salt);
  expect(base64Decode(parts[3]), hasLength(12));
  expect(base64Decode(parts[4]), hasLength(utf8.encode(plaintext).length + 16));
}

void main() {
  final cases = _loadCases();
  final crypto = KoiCryptoService();

  test('ATC-M14-01 fixture covers ASCII, Urdu, emoji and empty plaintexts', () {
    final names = cases.map((c) => c['name']).toSet();
    expect(names, containsAll(['ascii', 'urdu', 'emoji', 'empty']));
  });

  group('ATC-M14-01 web → Dart (decrypt web-generated payloads)', () {
    for (final c in cases) {
      test(c['name'] as String, () async {
        final payload = c['payload'] as String;
        _expectFormat(payload, c['salt'] as String, c['plaintext'] as String);
        final out = await crypto.decrypt(payload, c['secret'] as String);
        expect(out, c['plaintext']);
      }, timeout: _slow);
    }
  });

  group('ATC-M14-02 Dart → web (Node decrypts Dart-generated payloads)', () {
    late Directory tmp;
    setUpAll(() => tmp = Directory.systemTemp.createTempSync('koi_parity_'));
    tearDownAll(() => tmp.deleteSync(recursive: true));

    test('all cases', () async {
      final node = await Process.run('node', ['--version']);
      expect(node.exitCode, 0, reason: 'Node is required for this test');

      final dartCases = <Map<String, dynamic>>[];
      for (final c in cases) {
        final payload = await crypto.encrypt(c['plaintext'] as String,
            c['secret'] as String, c['salt'] as String);
        _expectFormat(payload, c['salt'] as String, c['plaintext'] as String);
        dartCases.add({...c, 'payload': payload});
      }
      final file = File('${tmp.path}/dart_payloads.json')
        ..writeAsStringSync(jsonEncode({'cases': dartCases}));

      final result = await Process.run('node', [_tool, 'verify', file.path],
          stdoutEncoding: utf8);
      // Show the Node tool's per-case PASS/FAIL lines in the test output.
      // ignore: avoid_print
      print(result.stdout);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      for (final c in cases) {
        expect(result.stdout as String, contains('PASS ${c['name']}'));
      }
    }, timeout: const Timeout(Duration(minutes: 10)));
  });

  group('ATC-M14-03 integrity (GCM tag is checked)', () {
    test('tampered web payload is rejected', () async {
      final c = cases.firstWhere((c) => c['name'] == 'ascii');
      final parts = (c['payload'] as String).split(':');
      final ct = base64Decode(parts[4]);
      ct[0] ^= 0x01;
      parts[4] = base64Encode(ct);
      await expectLater(
          crypto.decrypt(parts.join(':'), c['secret'] as String), throwsA(anything));
    }, timeout: _slow);

    test('wrong secret is rejected', () async {
      final c = cases.firstWhere((c) => c['name'] == 'ascii');
      await expectLater(crypto.decrypt(c['payload'] as String, 'wrong-secret'),
          throwsA(anything));
    }, timeout: _slow);
  });
}
