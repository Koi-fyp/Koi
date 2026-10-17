import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// What the fake server saw for one request. The test token is fake.
class SeenRequest {
  SeenRequest(this.method, this.uri, this.headers, this.body);
  final String method;
  final Uri uri;
  final HttpHeaders headers;
  final String body;

  String? header(String name) => headers.value(name);
  Map<String, Object?> get json =>
      Map<String, Object?>.from(jsonDecode(body) as Map);
}

typedef FakeHandler = Future<void> Function(HttpRequest req, SeenRequest seen);

/// A local HTTP server on 127.0.0.1 (like the reference client's test). No
/// real backend URL is used anywhere in the tests.
class FakeChatServer {
  FakeChatServer._(this._server);

  final HttpServer _server;
  final List<SeenRequest> requests = [];
  FakeHandler handler = (req, _) async {
    req.response.statusCode = 404;
    await req.response.close();
  };

  static Future<FakeChatServer> start() async {
    final server = FakeChatServer._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    server._server.listen((req) async {
      final body = await utf8.decodeStream(req);
      final seen = SeenRequest(req.method, req.uri, req.headers, body);
      // Send each flush at once (dart:io buffers the first write otherwise).
      req.response.bufferOutput = false;
      server.requests.add(seen);
      try {
        await server.handler(req, seen);
      } catch (_) {
        // The client went away (deadline tests).
      }
    });
    return server;
  }

  String get base => 'http://127.0.0.1:${_server.port}';

  Future<void> close() => _server.close(force: true);
}

/// Writes [frames] as SSE, [chunkBytes] bytes at a time so frames, lines
/// and multi-byte characters are split across chunks.
Future<void> writeSse(
  HttpRequest req,
  String frames, {
  int chunkBytes = 3,
}) async {
  req.response.headers.contentType = ContentType('text', 'event-stream');
  final bytes = utf8.encode(frames);
  for (var i = 0; i < bytes.length; i += chunkBytes) {
    final end = i + chunkBytes > bytes.length ? bytes.length : i + chunkBytes;
    req.response.add(bytes.sublist(i, end));
    await req.response.flush();
  }
  await req.response.close();
}

String sseFrame(String event, Object data) =>
    'event: $event\ndata: ${jsonEncode(data)}\n\n';

/// A normal turn: latency, companion_state, two deltas (the second with a
/// leading space), state, done.
String okTurn({
  String a = 'Hello',
  String b = ' there.',
  Object? exerciseState = 'tok-1',
}) =>
    sseFrame('latency', {'latency_ms': 12}) +
    sseFrame('companion_state', {'emotion': 'joy', 'intensity': 0.7}) +
    sseFrame('delta', {'text': a}) +
    sseFrame('delta', {'text': b}) +
    sseFrame('state', {'exercise_state': exerciseState}) +
    sseFrame('done', {
      'full_text': '$a$b',
      'companion_state': {'emotion': 'joy', 'intensity': 0.7},
      'exercise_state': exerciseState,
    });
