import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../safety/safety_contract.dart';
import 'chat_api.dart' show parseApiBase;

/// `POST {KOI_CRISIS_BASE}/api/v1/crisis` (contract §4): multipart, Bearer
/// token, 20 s timeout, fail closed (`null` on every error), like the
/// reference client's checkCrisis().
///
/// TODO(C8): whether clients call /api/v1/crisis at all is OPEN (contract
/// v1.1 C §C8). The chat server already scores risk every turn and sends the
/// `risk` event, so this runs only when KOI_CRISIS_BASE is set, in parallel
/// with chat, and its result only goes to SafetyController.handleRisk (never
/// into the chat request; C5).
class CrisisApiClient {
  CrisisApiClient({
    required String baseUrl,
    Dio? dio,
    this.timeout = const Duration(seconds: 20),
    this.healthTimeout = const Duration(seconds: 240),
  }) : base = parseApiBase(baseUrl),
       _dio = dio ?? Dio();

  final Uri? base;
  final Duration timeout;
  final Duration healthTimeout;
  final Dio _dio;

  bool get isConfigured => base != null;

  Uri _url(String path) => base!.replace(path: '${base!.path}$path');

  /// The typed message's risk, or null (not configured, error, timeout,
  /// non-2xx, bad JSON). null never means "safe".
  Future<RiskResult?> check({
    required Future<String> Function() idToken,
    required String text,
    String? turnId,
  }) async {
    if (!isConfigured) return null;
    final cancel = CancelToken();
    try {
      return await _check(idToken, text, turnId, cancel).timeout(timeout);
    } catch (_) {
      cancel.cancel();
      return null;
    }
  }

  Future<RiskResult?> _check(
    Future<String> Function() idToken,
    String text,
    String? turnId,
    CancelToken cancel,
  ) async {
    final token = await idToken();
    final res = await _dio.postUri<String>(
      _url('/api/v1/crisis'),
      data: FormData.fromMap({'text': text, 'turn_id': ?turnId}),
      cancelToken: cancel,
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        responseType: ResponseType.plain,
        followRedirects: false,
        validateStatus: (_) => true,
      ),
    );
    final status = res.statusCode ?? 0;
    if (status < 200 || status > 299) return null;
    final decoded = jsonDecode(res.data ?? '');
    if (decoded is! Map) return null;
    return RiskResult.fromJson({
      for (final e in decoded.entries)
        if (e.key is String) e.key as String: e.value,
    });
  }

  /// `GET {base}/health`, no token (C6). Only warms the service.
  Future<bool> checkHealth() async {
    if (!isConfigured) return false;
    try {
      final res = await _dio
          .getUri<String>(
            _url('/health'),
            options: Options(
              responseType: ResponseType.plain,
              validateStatus: (_) => true,
            ),
          )
          .timeout(healthTimeout);
      final s = res.statusCode ?? 0;
      return s >= 200 && s <= 299;
    } catch (_) {
      return false;
    }
  }
}
