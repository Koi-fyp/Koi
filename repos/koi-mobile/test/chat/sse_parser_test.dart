import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/avatar/avatar_state.dart';
import 'package:koi_mobile/chat/chat_api.dart';
import 'package:koi_mobile/core/emotion.dart';
import 'package:koi_mobile/safety/safety_contract.dart';

/// Feeds [text] through the parser the way the transport does: bytes split
/// every [n], decoded by one chunked utf8.decoder.
Future<SseChatParser> feedBytes(
  String text, {
  int n = 1,
  ChatHandlers handlers = const ChatHandlers(),
}) async {
  final parser = SseChatParser(handlers: handlers);
  final bytes = utf8.encode(text);
  final chunks = [
    for (var i = 0; i < bytes.length; i += n)
      bytes.sublist(i, i + n > bytes.length ? bytes.length : i + n),
  ];
  await for (final s in utf8.decoder.bind(Stream.fromIterable(chunks))) {
    parser.add(s);
  }
  parser.close();
  return parser;
}

void main() {
  test('ATC-M2-07 split UTF-8 (emoji + Urdu) one byte at a time', () async {
    final deltas = <String>[];
    final p = await feedBytes(
      'event: delta\ndata: {"text":"سلام 😀"}\n\n'
      'event: delta\ndata: {"text":" کیسے ہیں؟ 🌙"}\n\n'
      'event: done\ndata: {"full_text":"سلام 😀 کیسے ہیں؟ 🌙"}\n\n',
      handlers: ChatHandlers(onDelta: deltas.add),
    );
    expect(deltas, ['سلام 😀', ' کیسے ہیں؟ 🌙']);
    expect(p.fullText, 'سلام 😀 کیسے ہیں؟ 🌙');
  });

  test('ATC-M2-07 CRLF frames, data:/event: without a space, multi-line data', () {
    final p = SseChatParser()
      ..add('event:delta\r\ndata:{"text":"A"}\r\n\r\n')
      ..add('event: delta\r\ndata: {"text":\r\ndata: "B"}\r\n\r\n')
      ..close();
    expect(p.fullText, 'AB');
  });

  test('ATC-M2-08 C2: deltas are never trimmed; full_text == joined deltas', () {
    final deltas = <String>[];
    final p = SseChatParser(handlers: ChatHandlers(onDelta: deltas.add))
      ..add('event: delta\ndata: {"text":"Breathe in."}\n\n')
      ..add('event: delta\ndata: {"text":" Breathe out. "}\n\n')
      ..add('event: delta\ndata: {"text":"  Again."}\n\n');
    expect(deltas.join(), 'Breathe in. Breathe out.   Again.');
    expect(p.fullText, deltas.join());
    p
      ..add(
        'event: done\ndata: ${jsonEncode({'full_text': deltas.join()})}\n\n',
      )
      ..close();
    expect(p.fullText, 'Breathe in. Breathe out.   Again.');
  });

  test('ATC-M2-08 empty done.full_text keeps the deltas', () {
    final p = SseChatParser()
      ..add('event: delta\ndata: {"text":"x"}\n\n')
      ..add('event: done\ndata: {"full_text":""}\n\n');
    expect(p.fullText, 'x');
  });

  test('ATC-M2-07 event name resets to "message" for every frame', () {
    final p = SseChatParser()
      ..add('event: delta\ndata: {"text":"a"}\n\n')
      ..add('data: {"text":"b"}\n\n'); // a `message` frame, not a delta
    expect(p.fullText, 'a');
  });

  test('ATC-M2-07 unknown events and malformed JSON are ignored', () {
    final p = SseChatParser()
      ..add('event: delta\ndata: {not json\n\n')
      ..add('event: mystery\ndata: {"x":1}\n\n')
      ..add('event: transcript\ndata: {"text":"t","language":"ur"}\n\n')
      ..add('event: delta\ndata: [1,2]\n\n')
      ..add('event: delta\ndata: {"text":"ok"}\n\n');
    expect(p.fullText, 'ok');
  });

  test('ATC-M2-07 trailing frame without a blank line is flushed at close', () {
    final p = SseChatParser()..add('event: delta\ndata: {"text":"end"}');
    expect(p.fullText, '');
    p.close();
    expect(p.fullText, 'end');
  });

  group('ATC-M2-09 companion_state', () {
    test('arrives before text and goes to onCompanionState', () {
      final order = <String>[];
      SseChatParser(
          handlers: ChatHandlers(
            onCompanionState: (s) => order.add('state:${s.emotion.name}'),
            onDelta: (_) => order.add('delta'),
          ),
        )
        ..add(
          'event: companion_state\ndata: {"emotion":"sorrow","intensity":0.3}\n\n',
        )
        ..add('event: delta\ndata: {"text":"hi"}\n\n');
      expect(order, ['state:sorrow', 'delta']);
    });

    test('unknown emotion → neutral; intensity clamped; default 0.4', () {
      expect(
        CompanionState.fromJson({'emotion': 'happy', 'intensity': 3}).emotion,
        AvatarEmotion.neutral,
      );
      expect(
        CompanionState.fromJson({'emotion': 'fun', 'intensity': 3}).intensity,
        1.0,
      );
      expect(
        CompanionState.fromJson({'emotion': 'fun', 'intensity': -1}).intensity,
        0.0,
      );
      final missing = CompanionState.fromJson(null);
      expect(
        (missing.emotion, missing.intensity),
        (AvatarEmotion.neutral, 0.4),
      );
    });

    test('stored label: web storedEmotion() mapping', () {
      expect(storedEmotion('joy'), Emotion.happy);
      expect(storedEmotion('sorrow'), Emotion.sad);
      expect(storedEmotion('fun'), Emotion.calm);
      expect(storedEmotion('angry'), Emotion.neutral);
      expect(storedEmotion('neutral'), Emotion.neutral);
    });
  });

  test('ATC-M12-13 ui_action urgent only before text; handoff only to crisis', () {
    final actions = <(String, bool)>[];
    final handoffs = <Handoff>[];
    SseChatParser(
        handlers: ChatHandlers(
          onUiAction: (a, urgent) => actions.add((a.name, urgent)),
          onHandoff: handoffs.add,
        ),
      )
      ..add('event: ui_action\ndata: {"name":"stop_breathing","args":{}}\n\n')
      ..add('event: delta\ndata: {"text":"ok"}\n\n')
      ..add(
        'event: ui_action\ndata: {"name":"start_breathing","args":{"cycles":2}}\n\n',
      )
      ..add('event: handoff\ndata: {"to":"elsewhere","reason":"x"}\n\n')
      ..add('event: handoff\ndata: {"to":"crisis","reason":"risk"}\n\n');
    expect(actions, [('stop_breathing', true), ('start_breathing', false)]);
    expect(handoffs.single.reason, 'risk');
  });

  test('ATC-M12-13 risk: streamed once; done.risk used only if none was streamed', () {
    final risks = <RiskResult>[];
    SseChatParser(handlers: ChatHandlers(onRisk: risks.add))
      ..add('event: risk\ndata: {"status":"unavailable"}\n\n')
      ..add(
        'event: done\ndata: {"risk":{"status":"ok","risk_category":"HIGH"}}\n\n',
      );
    expect(risks.single.isUnavailable, isTrue);
    expect(risks.single.showsCrisisFlow, isFalse);

    final onlyDone = <RiskResult>[];
    SseChatParser(handlers: ChatHandlers(onRisk: onlyDone.add)).add(
      'event: done\ndata: {"risk":{"status":"ok","risk_category":"LOW"}}\n\n',
    );
    expect(onlyDone.single.riskCategory, RiskCategory.low);
  });

  group('ATC-M2-10 exercise_state (contract §1: echo what the last state gave)', () {
    test('a string is stored exactly', () {
      final p = SseChatParser()
        ..add('event: state\ndata: {"exercise_state":"a.b.c=="}\n\n');
      expect((p.exerciseStateChanged, p.exerciseState), (true, 'a.b.c=='));
    });

    test('an explicit null clears it', () {
      final p = SseChatParser()
        ..add('event: state\ndata: {"exercise_state":null}\n\n');
      expect((p.exerciseStateChanged, p.exerciseState), (true, null));
    });

    test('a missing key or a non-string leaves it unchanged', () {
      final p = SseChatParser()
        ..add('event: state\ndata: {}\n\n')
        ..add('event: state\ndata: {"exercise_state":42}\n\n')
        ..add('event: done\ndata: {"exercise_state":{"x":1}}\n\n');
      expect(p.exerciseStateChanged, isFalse);
    });

    test('done.exercise_state follows the same rule', () {
      final p = SseChatParser()
        ..add('event: state\ndata: {"exercise_state":"s1"}\n\n')
        ..add('event: done\ndata: {"exercise_state":null}\n\n');
      expect((p.exerciseStateChanged, p.exerciseState), (true, null));
    });
  });

  test('ATC-M2-11 latency_ms and event names for diagnostics', () {
    final p = SseChatParser()
      ..add('event: latency\ndata: {"latency_ms":412.6}\n\n')
      ..add('event: delta\ndata: {"text":"a"}\n\n')
      ..add('event: delta\ndata: {"text":"b"}\n\n');
    expect(p.latencyMs, 412);
    expect(p.eventNames, ['latency', 'delta']);
  });
}
