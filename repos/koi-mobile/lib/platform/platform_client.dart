import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Why a platform call failed. HTTP status first, then the server's code:
/// the contract v0.5.1/v0.5.2 flat `ErrorDTO` (`{code, request_id, retryable}`,
/// origin/feat/web-1-professional-publishing lifecycle-http.ts) or the
/// MOB-1 provisional nested `{"error": {"code"}}` still used by the
/// questionnaire endpoints (their realignment is a later batch).
enum PlatformErrorCode {
  /// KOI_PLATFORM_BASE is empty or invalid.
  notConfigured,
  network,
  timeout,

  /// 401 after one forced token refresh: the session has expired.
  unauthorized,

  /// 403: the capability is gone (relationship ended, wrong role).
  forbidden,
  notFound,

  /// 409 `revision_conflict`: the server has a newer revision.
  revisionConflict,

  /// 409 / 423 `attempt_submitted`: the attempt is locked.
  attemptSubmitted,

  /// Another 409.
  conflict,

  /// A mutation answered 401 `unauthenticated` (flat ErrorDTO) even with a
  /// fresh token: the server wants a sign-in within the last 5 minutes
  /// (contract semantics "auth_time within five minutes"; web
  /// service.ts:23). The app asks for the password again. This is NEVER
  /// a revoked access.
  reauthRequired,

  /// 429 `rate_limited`.
  rateLimited,

  /// 400 / 422 `invalid_request` (flat ErrorDTO).
  invalid,
  server,

  /// A 2xx body that is not the JSON the contract describes.
  badResponse,
}

class PlatformException implements Exception {
  const PlatformException(this.code, {this.status, this.body});

  final PlatformErrorCode code;
  final int? status;

  /// The decoded error body (only its codes are read; never logged).
  final Map<String, Object?>? body;

  /// The contract's flat ErrorDTO `code` (e.g. `not_found`), or null when
  /// the body is not one (e.g. a route that does not exist yet).
  String? get contractCode =>
      body?['code'] is String && body?['request_id'] is String
      ? body!['code'] as String
      : null;

  /// `error.current_revision` of a 409 revision conflict.
  int? get currentRevision {
    final e = body?['error'];
    return e is Map && e['current_revision'] is int
        ? e['current_revision'] as int
        : null;
  }

  @override
  String toString() => 'PlatformException(${code.name}, $status)';
}

@immutable
class PlatformHttpResponse {
  const PlatformHttpResponse(this.status, this.body);
  final int status;
  final String body;
}

/// The wire. [DioPlatformTransport] is the real one; tests use fakes.
abstract interface class PlatformTransport {
  /// Throws [PlatformException] (network / timeout) when nothing came back.
  Future<PlatformHttpResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  });
}

class DioPlatformTransport implements PlatformTransport {
  DioPlatformTransport({Dio? dio, this.timeout = const Duration(seconds: 15)})
    : _dio = dio ?? Dio();

  final Dio _dio;
  final Duration timeout;

  @override
  Future<PlatformHttpResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async {
    try {
      final res = await _dio.requestUri<String>(
        uri,
        data: body,
        options: Options(
          method: method,
          headers: headers,
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
          sendTimeout: timeout,
          receiveTimeout: timeout,
          // No redirects: an auth header must never follow one elsewhere.
          followRedirects: false,
        ),
      );
      return PlatformHttpResponse(res.statusCode ?? 0, res.data ?? '');
    } on DioException catch (e) {
      throw PlatformException(switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout => PlatformErrorCode.timeout,
        _ => PlatformErrorCode.network,
      });
    }
  }
}

/// Authenticated JSON calls to the KOI 2.0 platform API.
///
/// - Identity comes only from the Firebase ID token (Bearer), never the body.
/// - 401: one forced token refresh and one retry, then [unauthorized].
/// - 403: [onForbidden] runs (capability refresh), then [forbidden].
/// - Logs only the method, path template and status: never a body, token
///   or answer.
class PlatformClient {
  PlatformClient({
    required this.base,
    required this.transport,
    required this.idToken,
    required this.refreshIdToken,
    this.onForbidden,
  });

  final Uri? base;
  final PlatformTransport transport;
  final Future<String> Function() idToken;
  final Future<String> Function() refreshIdToken;
  void Function()? onForbidden;

  bool get isConfigured => base != null;

  Uri _uri(String path, Map<String, String>? query) {
    final b = base!;
    return b.replace(
      path: '${b.path}$path',
      queryParameters: query == null || query.isEmpty ? null : query,
    );
  }

  Future<Object?> getJson(String path, {Map<String, String>? query}) =>
      _call('GET', path, query: query);

  /// [idempotencyKey] becomes the `Idempotency-Key` header, which every
  /// contract v0.5.1 mutation requires. A retry of the same user action
  /// must reuse the same key.
  Future<Object?> sendJson(
    String method,
    String path,
    Map<String, Object?> body, {
    Map<String, String>? headers,
    String? idempotencyKey,
  }) => _call(
    method,
    path,
    body: jsonEncode(body),
    headers: {...?headers, 'Idempotency-Key': ?idempotencyKey},
  );

  Future<Object?> _call(
    String method,
    String path, {
    Map<String, String>? query,
    String? body,
    Map<String, String>? headers,
  }) async {
    if (base == null) {
      throw const PlatformException(PlatformErrorCode.notConfigured);
    }
    final uri = _uri(path, query);
    Future<PlatformHttpResponse> send(String token) => transport.send(
      method,
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json',
        ...?headers,
      },
      body: body,
    );

    String token;
    try {
      token = await idToken();
    } catch (_) {
      throw const PlatformException(PlatformErrorCode.unauthorized);
    }
    var res = await send(token);
    if (res.status == 401) {
      try {
        token = await refreshIdToken();
      } catch (_) {
        throw const PlatformException(
          PlatformErrorCode.unauthorized,
          status: 401,
        );
      }
      res = await send(token);
    }
    if (res.status >= 200 && res.status < 300) {
      if (res.body.trim().isEmpty) return null;
      try {
        return jsonDecode(res.body);
      } catch (_) {
        throw PlatformException(
          PlatformErrorCode.badResponse,
          status: res.status,
        );
      }
    }
    debugPrint('[KOI] platform: $method ${template(path)} → ${res.status}');
    final errorBody = _decodeError(res.body);
    final serverCode = switch (errorBody?['error']) {
      final Map<dynamic, dynamic> e => e['code'],
      _ => null,
    };
    final flat = PlatformException(
      PlatformErrorCode.server,
      body: errorBody,
    ).contractCode;
    if (res.status == 403) onForbidden?.call();
    throw PlatformException(
      switch (res.status) {
        401 when method != 'GET' && flat == 'unauthenticated' =>
          PlatformErrorCode.reauthRequired,
        401 => PlatformErrorCode.unauthorized,
        403 => PlatformErrorCode.forbidden,
        404 => PlatformErrorCode.notFound,
        409 when serverCode == 'revision_conflict' =>
          PlatformErrorCode.revisionConflict,
        409 || 423 when serverCode == 'attempt_submitted' =>
          PlatformErrorCode.attemptSubmitted,
        409 => PlatformErrorCode.conflict,
        429 => PlatformErrorCode.rateLimited,
        400 || 422 when flat == 'invalid_request' => PlatformErrorCode.invalid,
        _ => PlatformErrorCode.server,
      },
      status: res.status,
      body: errorBody,
    );
  }

  static Map<String, Object?>? _decodeError(String body) {
    try {
      final v = jsonDecode(body);
      return v is Map ? v.cast<String, Object?>() : null;
    } catch (_) {
      return null;
    }
  }

  /// `/api/v1/patient/attempts/a1b2/draft` → `/api/v1/patient/attempts/…/draft`:
  /// ids never reach the log. MOB-4: a kept segment is at most 32
  /// characters, so an invitation token (43-128 characters, possibly all
  /// lower-case letters) is always replaced.
  static String template(String path) => path
      .split('/')
      .map(
        (s) => RegExp(r'^[a-z][a-z_-]{0,31}$|^v\d+$').hasMatch(s) || s.isEmpty
            ? s
            : '…',
      )
      .join('/');
}

/// JSON helpers shared by the provisional DTO parsers: a wrong type is a
/// [FormatException], never a silent default for required fields.
Map<String, Object?> asJsonMap(Object? v, [String what = 'object']) {
  if (v is Map) return v.cast<String, Object?>();
  throw FormatException('Expected $what');
}

List<Object?> asJsonList(Object? v, [String what = 'list']) {
  if (v is List) return v.cast<Object?>();
  throw FormatException('Expected $what');
}

String reqString(Map<String, Object?> j, String key) {
  final v = j[key];
  if (v is String && v.isNotEmpty) return v;
  throw FormatException('Missing $key');
}

int reqInt(Map<String, Object?> j, String key) {
  final v = j[key];
  if (v is int) return v;
  throw FormatException('Missing $key');
}
