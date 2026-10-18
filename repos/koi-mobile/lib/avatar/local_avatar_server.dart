import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Serves the bundled avatar page (assets/avatar_local/, built by
/// avatar_bundle/) to the avatar WebView for KOI_AVATAR_URL=local.
///
/// Chromium can't `fetch()` file:///android_asset URLs, and the host page
/// fetches its VRM, so the page needs an http origin. This one is bound to
/// 127.0.0.1 only, on a port the OS picks, and serves only [routes]; every
/// other path is 404, other methods 405, and a Host header other than our
/// own origin 403 (no DNS rebinding). Started by the call screen's avatar
/// and closed with it.
abstract class LocalAvatarHost {
  /// Starts serving (once; later calls get the same origin).
  Future<Uri> start();

  /// Stops serving; open connections are dropped.
  Future<void> close();
}

typedef LocalAvatarHostFactory = LocalAvatarHost Function();

class LocalAvatarServer implements LocalAvatarHost {
  LocalAvatarServer({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const String assetDir = 'assets/avatar_local';

  /// The host page; it reads `?model=male|female` like /avatar-host.
  static const String pagePath = '/index.html';

  /// Path → (Flutter asset, content type). Nothing else is served.
  static const Map<String, (String, String)> routes = {
    '/': ('$assetDir/index.html', 'text/html; charset=utf-8'),
    pagePath: ('$assetDir/index.html', 'text/html; charset=utf-8'),
    '/avatar.js': ('$assetDir/avatar.js', 'text/javascript; charset=utf-8'),
    '/avatar.css': ('$assetDir/avatar.css', 'text/css; charset=utf-8'),
    // VRMAvatarRenderer fetches these exact URLs (AvatarWebViewHost.tsx).
    '/models/koi-male.vrm': (
      '$assetDir/models/koi-male.vrm',
      'model/gltf-binary',
    ),
    '/models/koi-female.vrm': (
      '$assetDir/models/koi-female.vrm',
      'model/gltf-binary',
    ),
  };

  final AssetBundle _bundle;
  HttpServer? _server;
  Future<Uri>? _starting;
  bool _closed = false;

  @override
  Future<Uri> start() => _starting ??= _bind();

  Future<Uri> _bind() async {
    if (_closed) throw StateError('closed');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    if (_closed) {
      await server.close(force: true);
      throw StateError('closed');
    }
    _server = server
      ..autoCompress = false
      ..defaultResponseHeaders.clear()
      ..listen(
        _handle,
        onError: (Object e) {
          debugPrint('KOI: avatar server error: ${e.runtimeType}');
        },
      );
    return originFor(server.port);
  }

  /// `http://127.0.0.1:<port>`.
  static Uri originFor(int port) =>
      Uri(scheme: 'http', host: '127.0.0.1', port: port);

  /// The bound address (tests).
  @visibleForTesting
  InternetAddress? get address => _server?.address;

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final port = _server?.port;
      final route = routes[request.uri.path];
      if (request.headers.value(HttpHeaders.hostHeader) != '127.0.0.1:$port') {
        response.statusCode = HttpStatus.forbidden;
      } else if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
      } else if (route == null) {
        response.statusCode = HttpStatus.notFound;
      } else {
        final (asset, contentType) = route;
        final data = await _bundle.load(asset);
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        response.headers
          ..set(HttpHeaders.contentTypeHeader, contentType)
          ..set(HttpHeaders.cacheControlHeader, 'no-store')
          ..set('X-Content-Type-Options', 'nosniff');
        response.contentLength = bytes.length;
        if (request.method == 'GET') response.add(bytes);
      }
    } catch (e) {
      debugPrint('KOI: avatar asset not served: ${e.runtimeType}');
      response.statusCode = HttpStatus.internalServerError;
    }
    try {
      await response.close();
    } catch (_) {
      // The WebView went away mid-response.
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }
}
