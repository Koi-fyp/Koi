import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/avatar/local_avatar_server.dart';

/// Every asset key the server may ask for, plus things it must never serve.
class _FakeBundle extends AssetBundle {
  _FakeBundle(this.files);
  final Map<String, String> files;
  final requested = <String>[];

  @override
  Future<ByteData> load(String key) async {
    requested.add(key);
    final text = files[key];
    if (text == null) throw FlutterError('no asset $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));
  }

  @override
  Future<T> loadStructuredData<T>(
    String key,
    Future<T> Function(String value) parser,
  ) async => parser(await loadString(key));
}

/// A raw HTTP/1.1 request, so paths and Host headers go out exactly as
/// written (HttpClient would normalize them).
Future<(int, String)> _raw(
  int port,
  String method,
  String path, {
  String? host,
}) async {
  final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
  socket.write(
    '$method $path HTTP/1.1\r\n'
    'Host: ${host ?? '127.0.0.1:$port'}\r\n'
    'Connection: close\r\n\r\n',
  );
  await socket.flush();
  final text = await utf8.decoder.bind(socket).join();
  socket.destroy();
  final status = int.parse(text.split(' ')[1]);
  return (status, text.substring(text.indexOf('\r\n\r\n') + 4));
}

void main() {
  late _FakeBundle bundle;
  late LocalAvatarServer server;
  late int port;

  setUp(() async {
    bundle = _FakeBundle({
      for (final (asset, _) in LocalAvatarServer.routes.values)
        asset: 'body of $asset',
      // Present in the bundle but not allowlisted: must never be served.
      'assets/avatar_mock/mock_avatar.html': 'mock',
      'assets/images/Male.png': 'png',
      'pubspec.yaml': 'secret',
    });
    server = LocalAvatarServer(bundle: bundle);
    port = (await server.start()).port;
  });

  tearDown(() => server.close());

  test('binds to 127.0.0.1 only, on an OS-picked port', () async {
    expect(server.address, InternetAddress.loopbackIPv4);
    expect(server.address!.isLoopback, isTrue);
    expect(port, greaterThan(0));
    expect(
      await server.start(),
      Uri.parse('http://127.0.0.1:$port'),
      reason: 'start() is idempotent',
    );
  });

  test(
    'serves exactly the allowlisted paths, with fixed content types',
    () async {
      final client = HttpClient();
      addTearDown(client.close);
      for (final MapEntry(key: path, value: (asset, type))
          in LocalAvatarServer.routes.entries) {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:$port$path'),
        );
        final response = await request.close();
        final body = await utf8.decoder.bind(response).join();
        expect(response.statusCode, 200, reason: path);
        expect(body, 'body of $asset', reason: path);
        expect(response.headers.contentType.toString(), type, reason: path);
        expect(response.headers.value('x-content-type-options'), 'nosniff');
      }
      expect(LocalAvatarServer.routes.keys, {
        '/',
        '/index.html',
        '/avatar.js',
        '/avatar.css',
        '/models/koi-male.vrm',
        '/models/koi-female.vrm',
      });
    },
  );

  test('everything else is 404 and never read from the bundle', () async {
    for (final path in [
      '/models/',
      '/models/fox.glb',
      '/index.htm',
      '/index.html/',
      '/AVATAR.JS',
      '//avatar.js',
      '/assets/avatar_local/index.html',
      '/assets/avatar_mock/mock_avatar.html',
      '/assets/images/Male.png',
      '/pubspec.yaml',
      '/%2e%2e/pubspec.yaml',
      '/models/%2e%2e/%2e%2e/pubspec.yaml',
      '/..%2fpubspec.yaml',
      '/favicon.ico',
    ]) {
      final (status, body) = await _raw(port, 'GET', path);
      expect(status, 404, reason: path);
      expect(body, isNot(contains('secret')), reason: path);
    }
    final allowed = {
      for (final (asset, _) in LocalAvatarServer.routes.values) asset,
    };
    expect(bundle.requested.toSet().difference(allowed), isEmpty);
  });

  test('only GET and HEAD; HEAD has no body', () async {
    for (final method in ['POST', 'PUT', 'DELETE', 'OPTIONS']) {
      final (status, _) = await _raw(port, method, '/index.html');
      expect(status, 405, reason: method);
    }
    final (status, body) = await _raw(port, 'HEAD', '/avatar.js');
    expect(status, 200);
    expect(body, isEmpty);
  });

  test('a Host other than our own origin is refused (DNS rebinding)', () async {
    for (final host in [
      'evil.example.com',
      'localhost:$port',
      '127.0.0.1',
      '127.0.0.1:${port + 1}',
    ]) {
      final (status, body) = await _raw(port, 'GET', '/index.html', host: host);
      expect(status, 403, reason: host);
      expect(body, isNot(contains('body of')), reason: host);
    }
  });

  test('a missing bundled file is a 500, not a crash', () async {
    bundle.files.remove('assets/avatar_local/avatar.css');
    final (status, _) = await _raw(port, 'GET', '/avatar.css');
    expect(status, 500);
    final (ok, _) = await _raw(port, 'GET', '/avatar.js');
    expect(ok, 200);
  });

  test('close() stops serving', () async {
    await server.close();
    await expectLater(
      Socket.connect(InternetAddress.loopbackIPv4, port),
      throwsA(isA<SocketException>()),
    );
    await expectLater(server.start(), completes, reason: 'same future');
    final fresh = LocalAvatarServer(bundle: bundle);
    await fresh.close();
    await expectLater(fresh.start(), throwsStateError);
  });
}
