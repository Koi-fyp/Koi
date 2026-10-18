import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/avatar/local_avatar_server.dart';

/// `git hash-object` of [bytes]: SHA-1 of `blob <size>\0` + bytes.
Future<String> _gitBlobId(List<int> bytes) async {
  final hash = await Sha1().hash([
    ...utf8.encode('blob ${bytes.length}'),
    0,
    ...bytes,
  ]);
  return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Upstream: repos/koi-backend/nextjs_app/ at origin/feat/avatar-webview-host
/// 223e97c (`git ls-tree 223e97c -- <path>`).
const _upstreamBlobs = {
  'src/components/avatar/AvatarWebViewHost.tsx':
      '0c58b46efec60f11e690fd8db3df6ec6a951241f',
  'src/components/avatar/AvatarWebViewHost.module.css':
      '3388dfbcf68ee66838380880fbd6153f8eb307d5',
  'src/components/avatar/VRMAvatarRenderer.tsx':
      '71b81044525395b44ddadc603f34f19c987289d5',
  'src/components/avatar/VRMAvatarController.ts':
      'edbc51296de6a7112b6b07a946570408ea97fe86',
  'src/components/avatar/VRMMouthController.ts':
      '8e9bed948406a9d96c43cd6d7141a21d0719addb',
  'src/components/avatar/avatarCommandBridge.ts':
      '3fb4e557a5c7f3f5021897aced7a17d115431107',
  'src/lib/speech/mouthCues.ts': '9fb1c436db5e2dfe820a4350e1821e409d8154f0',
};

void main() {
  test('every served file is bundled and listed in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(pubspec, contains('    - assets/avatar_local/\n'));
    expect(pubspec, contains('    - assets/avatar_local/models/\n'));
    for (final (asset, _) in LocalAvatarServer.routes.values) {
      expect(File(asset).existsSync(), isTrue, reason: asset);
    }
  });

  test('the VRMs are byte-for-byte Fatima\'s (git blob ids)', () async {
    const blobs = {
      'koi-male.vrm': '07c30ad867ea3a618eeab9914135bd360dc36efe',
      'koi-female.vrm': '0999b8e3458995ab29ee6639c8be52d10c8a9a07',
    };
    for (final MapEntry(key: name, value: id) in blobs.entries) {
      final bytes = File('assets/avatar_local/models/$name').readAsBytesSync();
      expect(await _gitBlobId(bytes), id, reason: name);
    }
  });

  test('copied sources = upstream + the two-line header only', () async {
    for (final MapEntry(key: path, value: id) in _upstreamBlobs.entries) {
      final text = File('avatar_bundle/$path')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      final lines = text.split('\n');
      expect(
        lines.take(2).join('\n'),
        allOf(
          contains('repos/koi-backend/nextjs_app/$path'),
          contains('feat/avatar-webview-host'),
          contains('223e97c'),
          contains('do not edit here'),
        ),
        reason: path,
      );
      final body = lines.skip(2).join('\n');
      expect(await _gitBlobId(utf8.encode(body)), id, reason: path);
    }
  });

  test('the page only talks to its own origin', () {
    final html = File('assets/avatar_local/index.html').readAsStringSync();
    final csp = RegExp(
      r'''http-equiv="Content-Security-Policy" content="([^"]*)"''',
    ).firstMatch(html)?.group(1);
    expect(csp, isNotNull);
    expect(csp, contains("default-src 'self'"));
    expect(csp, contains("script-src 'self'"));
    expect(csp, contains("connect-src 'self' blob: data:"));
    expect(csp, isNot(contains('http')));
    expect(csp, isNot(contains('*')));
    expect(csp, isNot(contains('unsafe')));
    // Only same-origin, relative script and style files.
    expect(RegExp(r'(src|href)="([^"]*)"').allMatches(html).map((m) => m[2]), [
      'avatar.css',
      'avatar.js',
    ]);
    expect(html, contains('viewport-fit=cover'));
  });

  test('the built page has the bridge contract and the hasOwn polyfill', () {
    final js = File('assets/avatar_local/avatar.js').readAsStringSync();
    expect(js, contains('AVATAR_READY'));
    expect(js, contains('AvatarController'));
    expect(js, contains('KoiBridge'));
    expect(js, contains('/models/koi-male.vrm'));
    expect(js, contains('/models/koi-female.vrm'));
    expect(
      js,
      contains('Object.hasOwn||Object.defineProperty(Object,"hasOwn"'),
    );
    // Fatima's .tsx files use the automatic JSX runtime (as Next.js does);
    // a classic-JSX build references a global React and renders nothing.
    expect(js, isNot(contains('React.createElement')));
  });
}
