import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/chat/crisis_api.dart';
import 'package:koi_mobile/safety/safety_contract.dart';

import '../support/fake_chat_server.dart';

void main() {
  late FakeChatServer server;
  setUp(() async => server = await FakeChatServer.start());
  tearDown(() => server.close());

  Future<String> token() async => 'fake-test-token';

  test('not configured → null, nothing called', () async {
    final c = CrisisApiClient(baseUrl: '');
    expect(c.isConfigured, isFalse);
    expect(await c.check(idToken: token, text: 'x'), isNull);
  });

  test('multipart POST with Bearer; parses the result', () async {
    server.handler = (req, _) async {
      req.response.write(
        jsonEncode({
          'crisis_score': 0.8,
          'risk_category': 'HIGH',
          'modalities_used': ['text'],
          'trigger_flags': [],
          'confidence': 'reduced',
        }),
      );
      await req.response.close();
    };
    final r = await CrisisApiClient(baseUrl: server.base)
        .check(idToken: token, text: 'typed', turnId: '3');
    expect(r!.riskCategory, RiskCategory.high);
    expect(r.isReducedConfidence, isTrue);
    final seen = server.requests.single;
    expect(seen.uri.path, '/api/v1/crisis');
    expect(seen.header('authorization'), 'Bearer fake-test-token');
    expect(seen.header('content-type'), startsWith('multipart/form-data'));
    expect(seen.body, contains('name="text"'));
    expect(seen.body, contains('name="turn_id"'));
  });

  test('fails closed: non-2xx, bad JSON, token error, timeout', () async {
    var mode = 'status';
    server.handler = (req, _) async {
      switch (mode) {
        case 'status':
          req.response.statusCode = 500;
        case 'json':
          req.response.write('not json');
        case 'slow':
          await Future<void>.delayed(const Duration(seconds: 2));
          req.response.write('{}');
      }
      await req.response.close();
    };
    final c = CrisisApiClient(
      baseUrl: server.base,
      timeout: const Duration(milliseconds: 300),
    );
    expect(await c.check(idToken: token, text: 'x'), isNull);
    mode = 'json';
    expect(await c.check(idToken: token, text: 'x'), isNull);
    expect(
      await c.check(idToken: () async => throw StateError('no'), text: 'x'),
      isNull,
    );
    mode = 'slow';
    expect(await c.check(idToken: token, text: 'x'), isNull);
  });

  test('the default timeout is 20 s', () {
    expect(CrisisApiClient(baseUrl: '').timeout, const Duration(seconds: 20));
  });

  test('/health without Authorization', () async {
    server.handler = (req, _) async {
      req.response.write('{"status":"ok"}');
      await req.response.close();
    };
    expect(await CrisisApiClient(baseUrl: server.base).checkHealth(), isTrue);
    expect(server.requests.single.uri.path, '/health');
    expect(server.requests.single.header('authorization'), isNull);
  });
}
