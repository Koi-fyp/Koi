import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/avatar/avatar_source.dart';
import 'package:koi_mobile/avatar/avatar_view.dart';

/// The JSON-encoded arguments of a [AvatarViewController.jsCall] result.
List<Object?> argsOf(String js) {
  final open = js.indexOf('(', js.indexOf('window.AvatarController.'));
  final close = js.lastIndexOf(')');
  return jsonDecode('[${js.substring(open + 1, close)}]') as List<Object?>;
}

void main() {
  group('AvatarViewController bridge', () {
    late AvatarViewController c;
    late List<String> sent;
    late int reloads;
    final token = Object();

    setUp(() {
      c = AvatarViewController();
      sent = [];
      reloads = 0;
      c.attachPage(
        token,
        run: (js) async => sent.add(js),
        reload: () => reloads++,
      );
    });
    tearDown(() => c.dispose());

    test('ATC-M21-02 nothing is sent before AVATAR_READY; other messages ignored', () {
      c.beginLoad();
      c.setEmotion(AvatarEmotion.joy, 0.5);
      c.handleBridgeMessage('HELLO');
      c.handleBridgeMessage('avatar_ready');
      expect(sent, isEmpty);
      expect(c.status, AvatarStatus.loading);
    });

    test('ATC-M21-02 only the latest queued emotion is sent, once, after ready', () {
      c.beginLoad();
      c.setEmotion(AvatarEmotion.joy, 0.5);
      c.setEmotion(AvatarEmotion.sorrow, 0.2);
      c.setEmotion(AvatarEmotion.angry, 0.3);
      c.handleBridgeMessage('AVATAR_READY');

      expect(c.isReady, isTrue);
      expect(sent, [
        'window.AvatarController && '
            'window.AvatarController.setEmotion("angry", 0.3);',
        'window.AvatarController && '
            'window.AvatarController.setConversationState("idle");',
      ]);
      c.handleBridgeMessage('AVATAR_READY'); // duplicate: nothing more
      expect(sent, hasLength(2));

      c.setEmotion(AvatarEmotion.fun, 1);
      expect(argsOf(sent.last), ['fun', 1.0]);
      expect(sent, hasLength(3));
    });

    test('ATC-M21-02 after a reload the current emotion is sent again once ready', () {
      c.beginLoad();
      c.handleBridgeMessage('AVATAR_READY');
      c.setEmotion(AvatarEmotion.joy, 0.7);
      sent.clear();

      c.beginLoad(); // page reloaded (onPageStarted)
      expect(c.isReady, isFalse);
      c.setEmotion(AvatarEmotion.joy, 0.7); // unchanged → nothing to send
      expect(sent, isEmpty);
      c.handleBridgeMessage('AVATAR_READY');
      expect(sent.map(argsOf), [
        ['joy', 0.7],
        ['idle'],
      ]);
    });

    test('ATC-M21-03 conversation state: nothing before AVATAR_READY, only the latest '
        'is sent once ready, then each change is sent', () {
      c.beginLoad();
      c.setConversationState(AvatarConversationState.listening);
      c.setConversationState(AvatarConversationState.thinking);
      expect(sent, isEmpty);
      expect(c.conversationState, AvatarConversationState.thinking);

      c.handleBridgeMessage('AVATAR_READY');
      final states = sent
          .where(
            (s) =>
                s.contains(AvatarViewController.setConversationStateFunction),
          )
          .toList();
      expect(states, [
        'window.AvatarController && '
            'window.AvatarController.setConversationState("thinking");',
      ]);

      sent.clear();
      c.setConversationState(AvatarConversationState.speaking);
      c.setConversationState(AvatarConversationState.speaking); // unchanged
      expect(sent, [
        'window.AvatarController && '
            'window.AvatarController.setConversationState("speaking");',
      ]);
      expect(argsOf(sent.single), ['speaking']);
    });

    test('ATC-M21-03 after a reload the conversation state is sent again with the '
        'emotion once ready', () {
      c.beginLoad();
      c.handleBridgeMessage('AVATAR_READY');
      c.setEmotion(AvatarEmotion.sorrow, 0.4);
      c.setConversationState(AvatarConversationState.listening);
      sent.clear();

      c.beginLoad(); // page reloaded (onPageStarted) or Reconnect
      c.setConversationState(AvatarConversationState.speaking); // queued
      expect(sent, isEmpty);
      c.handleBridgeMessage('AVATAR_READY');
      expect(sent.map(argsOf), [
        ['sorrow', 0.4],
        ['speaking'],
      ]);
    });

    test('ATC-M21-03 a detached page gets no conversation state', () {
      c.beginLoad();
      c.handleBridgeMessage('AVATAR_READY');
      c.detachPage(token);
      sent.clear();
      c.setConversationState(AvatarConversationState.thinking);
      expect(sent, isEmpty);
    });

    test('ATC-M21-04 reconnect asks the view to load the page again', () {
      c.markFailed();
      c.reconnect();
      expect(reloads, 1);
    });

    test('ATC-M21-04 a detached page can no longer make the avatar ready', () {
      c.beginLoad();
      c.detachPage(token);
      c.handleBridgeMessage('AVATAR_READY');
      expect(c.isReady, isFalse);
    });

    test('ATC-M21-04 a stale token cannot detach the current page', () {
      c.detachPage(Object());
      c.beginLoad();
      c.handleBridgeMessage('AVATAR_READY');
      expect(c.isReady, isTrue);
    });

    testWidgets('ATC-M21-04 no AVATAR_READY within 20 s → failed; ready recovers', (
      tester,
    ) async {
      // testWidgets runs timers on a fake clock.
      final t = AvatarViewController();
      t.attachPage(token, run: (js) async => sent.add(js), reload: () {});
      t.beginLoad();
      await tester.pump(const Duration(seconds: 19));
      expect(t.status, AvatarStatus.loading);
      await tester.pump(const Duration(seconds: 1));
      expect(t.status, AvatarStatus.failed);

      t.beginLoad(); // Reconnect
      t.handleBridgeMessage('AVATAR_READY');
      await tester.pump(const Duration(seconds: 30));
      expect(t.status, AvatarStatus.ready); // timer was cancelled
      t.dispose();
    });

    test('ATC-M21-04 avatar is Dart state only', () {
      c.beginLoad();
      c.handleBridgeMessage('AVATAR_READY');
      sent.clear();
      c.setAvatar(AvatarType.female);
      expect(c.avatar, AvatarType.female);
      expect(sent, isEmpty);
    });

    test('ATC-M3-18 mouth cues: KoiSpeech only after ready, via jsonEncode', () {
      c.beginLoad();
      const cues = [
        MouthCue(start: 0, end: 0.2, value: 'D'),
        MouthCue(start: 0.2, end: 0.5, value: 'X'),
      ];
      c.setMouthCues(cues);
      c.setMouthCues(const []);
      expect(sent, isEmpty, reason: 'not ready: dropped, never queued');
      c.handleBridgeMessage('AVATAR_READY');
      expect(sent.where((js) => js.contains('KoiSpeech')), isEmpty);
      sent.clear();

      c.setMouthCues(cues);
      expect(c.mouthCues, hasLength(2));
      final js = sent.single;
      expect(js, startsWith('window.KoiSpeech && window.KoiSpeech.start("'));
      final open = js.indexOf('(', js.indexOf('window.KoiSpeech.'));
      final arg = jsonDecode(js.substring(open + 1, js.lastIndexOf(')')));
      expect(arg, isA<String>(), reason: 'cuesJson is a JS string literal');
      expect(jsonDecode(arg as String), [
        {'start': 0.0, 'end': 0.2, 'value': 'D'},
        {'start': 0.2, 'end': 0.5, 'value': 'X'},
      ]);

      sent.clear();
      c.setMouthCues(const []);
      expect(sent, ['window.KoiSpeech && window.KoiSpeech.stop();']);
    });

    test('ATC-M3-18 a hostile cue value stays inside the string literal', () {
      c.beginLoad();
      c.handleBridgeMessage('AVATAR_READY');
      sent.clear();
      c.setMouthCues(const [
        MouthCue(start: 0, end: 1, value: '");alert(1);("'),
      ]);
      final js = sent.single;
      final open = js.indexOf('(', js.indexOf('window.KoiSpeech.'));
      final arg = jsonDecode(js.substring(open + 1, js.lastIndexOf(')')));
      expect(
        (jsonDecode(arg as String) as List).single['value'],
        '");alert(1);("',
      );
      expect(js, endsWith('");'));
    });
  });

  group('ATC-M21-05 jsCall', () {
    test('every argument is JSON-encoded (quotes, Urdu, emoji, </script>)', () {
      const tricky = [
        'he said "hi"',
        "it's \\ done",
        '");alert(1);//',
        'میں خوش ہوں',
        '😊🐟',
        '</script><script>x()</script>',
        'line\nbreak sep',
      ];
      for (final value in tricky) {
        final js = AvatarViewController.jsCall(
          AvatarViewController.setEmotionFunction,
          [value, 0.5],
        );
        expect(argsOf(js), [value, 0.5], reason: value);
        expect(js, startsWith('window.AvatarController && '));
        // Exactly the JSON string literal: the value cannot end it early.
        expect(js, contains("(${jsonEncode(value)}, 0.5)"));

        final stateJs = AvatarViewController.jsCall(
          AvatarViewController.setConversationStateFunction,
          [value],
        );
        expect(argsOf(stateJs), [value], reason: value);
        expect(
          stateJs,
          'window.AvatarController && '
          'window.AvatarController.setConversationState(${jsonEncode(value)});',
        );
      }
    });

    test('only the fixed avatar functions can be called', () {
      expect(
        () => AvatarViewController.jsCall('alert', ['x']),
        throwsArgumentError,
      );
      for (final notAllowed in [
        'AvatarController.reset',
        'AvatarController.getSnapshot',
        'KoiBridge.postMessage',
      ]) {
        expect(
          () => AvatarViewController.jsCall(notAllowed, const []),
          throwsArgumentError,
          reason: notAllowed,
        );
      }
      expect(
        AvatarViewController.jsCall(
          AvatarViewController.setConversationStateFunction,
          ['idle'],
        ),
        'window.AvatarController && '
        'window.AvatarController.setConversationState("idle");',
      );
    });

    test('setEmotion uses the host emotion names', () {
      expect(AvatarEmotion.values.map((e) => e.name), [
        'neutral',
        'joy',
        'angry',
        'sorrow',
        'fun',
      ]);
      expect(AvatarConversationState.values.map((e) => e.name), [
        'idle',
        'listening',
        'thinking',
        'speaking',
      ]);
    });
  });

  group('ATC-M21-06 sessions', () {
    test('updates for an old session id are dropped', () {
      final c = AvatarViewController();
      addTearDown(c.dispose);

      // Before any session: dropped.
      expect(
        c.apply(const AvatarStateUpdate('s1', emotion: AvatarEmotion.joy)),
        isFalse,
      );
      c.apply(const AvatarSessionStarted('s1'));
      expect(
        c.apply(
          const AvatarStateUpdate(
            's1',
            emotion: AvatarEmotion.joy,
            intensity: 0.6,
            conversationState: AvatarConversationState.listening,
          ),
        ),
        isTrue,
      );
      expect((c.emotion, c.intensity), (AvatarEmotion.joy, 0.6));

      c.apply(const AvatarSessionStarted('s2'));
      expect(
        c.apply(
          const AvatarStateUpdate(
            's1',
            emotion: AvatarEmotion.angry,
            intensity: 1,
            conversationState: AvatarConversationState.speaking,
          ),
        ),
        isFalse,
      );
      expect(c.emotion, AvatarEmotion.joy);
      expect(c.conversationState, AvatarConversationState.listening);

      c.apply(
        const AvatarStateUpdate(
          's2',
          emotion: AvatarEmotion.sorrow,
          intensity: 2,
        ),
      );
      expect((c.emotion, c.intensity), (AvatarEmotion.sorrow, 1.0));
    });

    test(
      'simulator: sessions get new ids, events reach the controller',
      () async {
        final sim = SimulatedAvatarStateSource();
        addTearDown(sim.dispose);
        final c = AvatarViewController();
        addTearDown(c.dispose);
        sim.events.listen(c.apply);

        final s1 = sim.startSession();
        final s2 = sim.startSession();
        expect(s1, isNot(s2));
        sim.emit(
          AvatarStateUpdate(s1, emotion: AvatarEmotion.fun, intensity: 1),
        );
        sim.emit(
          AvatarStateUpdate(s2, emotion: AvatarEmotion.joy, intensity: 1),
        );
        await Future<void>.delayed(Duration.zero);
        expect(c.sessionId, s2);
        expect(c.emotion, AvatarEmotion.joy);
      },
    );
  });

  group('AvatarSource', () {
    test('ATC-M21-07 KOI_AVATAR_URL: empty → placeholder, mock (debug only), https', () {
      expect(AvatarSource.parse(''), AvatarSource.placeholder);
      expect(AvatarSource.parse('   '), AvatarSource.placeholder);
      expect(AvatarSource.parse('mock', debug: true), AvatarSource.mock);
      expect(
        AvatarSource.parse('mock', debug: false),
        AvatarSource.placeholder,
      );
      expect(
        AvatarSource.parse('https://koi.example.com/avatar-host').kind,
        AvatarSourceKind.remote,
      );
      for (final bad in [
        'http://koi.example.com/avatar-host',
        'javascript:alert(1)',
        'file:///sdcard/x.html',
        'koi.example.com',
      ]) {
        expect(AvatarSource.parse(bad), AvatarSource.placeholder, reason: bad);
      }
    });

    test('ATC-M21-07 page URL adds ?model= and keeps other query parameters', () {
      final s = AvatarSource.parse('https://koi.example.com/avatar-host?v=2#x');
      expect(
        s.pageUrl(AvatarType.female).toString(),
        'https://koi.example.com/avatar-host?v=2&model=female',
      );
      expect(s.pageUrl(AvatarType.male).queryParameters['model'], 'male');
    });

    test('ATC-M21-08 navigation stays on the avatar origin', () {
      final s = AvatarSource.parse('https://koi.example.com/avatar-host');
      for (final ok in [
        'https://koi.example.com/avatar-host?model=male',
        'https://KOI.example.com/models/koi-male.vrm',
        'https://koi.example.com:443/avatar-host',
      ]) {
        expect(s.allowsNavigation(ok), isTrue, reason: ok);
      }
      for (final blocked in [
        'https://evil.example.com/avatar-host',
        'https://koi.example.com.evil.com/',
        'http://koi.example.com/avatar-host',
        'https://koi.example.com:8443/avatar-host',
        'https://user:pw@koi.example.com/avatar-host',
        'https://koi.example.com@evil.com/',
        'javascript:alert(1)',
        'intent://x#Intent;end',
        'about:blank',
        'file:///android_asset/flutter_assets/${AvatarSource.mockAsset}',
      ]) {
        expect(s.allowsNavigation(blocked), isFalse, reason: blocked);
      }
    });

    test('ATC-M21-07 local: KOI_AVATAR_URL=local works in debug and release', () {
      expect(AvatarSource.parse('local', debug: true), AvatarSource.local);
      expect(AvatarSource.parse('local', debug: false), AvatarSource.local);
      expect(AvatarSource.parse(' local '), AvatarSource.local);
      expect(AvatarSource.parse('LOCAL'), AvatarSource.placeholder);
      expect(AvatarSource.local.usesWebView, isTrue);
      expect(AvatarSource.local.url, isNull);
    });

    test('ATC-M21-07 local page URL: the bundled host page with ?model=male|female', () {
      final origin = Uri.parse('http://127.0.0.1:40123');
      expect(
        AvatarSource.localPageUrl(origin, AvatarType.male).toString(),
        'http://127.0.0.1:40123/index.html?model=male',
      );
      expect(
        AvatarSource.localPageUrl(origin, AvatarType.female).toString(),
        'http://127.0.0.1:40123/index.html?model=female',
      );
    });

    test('ATC-M21-08 local navigation: only the host page on our own loopback port', () {
      final origin = Uri.parse('http://127.0.0.1:40123');
      const s = AvatarSource.local;
      for (final ok in [
        'http://127.0.0.1:40123/index.html?model=male',
        'http://127.0.0.1:40123/index.html?model=female',
        'http://127.0.0.1:40123/?model=female',
      ]) {
        expect(s.allowsNavigation(ok, localOrigin: origin), isTrue, reason: ok);
      }
      for (final blocked in [
        'http://127.0.0.1:40124/index.html?model=male',
        'http://localhost:40123/index.html?model=male',
        'http://127.0.0.2:40123/index.html?model=male',
        'https://127.0.0.1:40123/index.html?model=male',
        'http://127.0.0.1:40123/index.html',
        'http://127.0.0.1:40123/index.html?model=fox',
        'http://127.0.0.1:40123/index.html?model=male&x=1',
        'http://127.0.0.1:40123/index.html?model=male&model=female',
        'http://127.0.0.1:40123/index.html?model=male#x',
        'http://u:p@127.0.0.1:40123/index.html?model=male',
        'http://127.0.0.1:40123/avatar.js?model=male',
        'http://127.0.0.1:40123/models/koi-male.vrm?model=male',
        'https://koi.example.com/avatar-host?model=male',
        'file:///android_asset/flutter_assets/${AvatarSource.mockAsset}',
        'javascript:alert(1)',
        'intent://x#Intent;end',
        'about:blank',
      ]) {
        expect(
          s.allowsNavigation(blocked, localOrigin: origin),
          isFalse,
          reason: blocked,
        );
      }
      // Server not up yet: nothing.
      expect(
        s.allowsNavigation('http://127.0.0.1:40123/index.html?model=male'),
        isFalse,
      );
    });

    test('ATC-M21-07 mock may only show its own asset; placeholder nothing', () {
      expect(
        AvatarSource.mock.allowsNavigation(
          'file:///android_asset/flutter_assets/${AvatarSource.mockAsset}#fail',
        ),
        isTrue,
      );
      expect(
        AvatarSource.mock.allowsNavigation(
          'file:///android_asset/flutter_assets/assets/images/Male.png',
        ),
        isFalse,
      );
      expect(
        AvatarSource.mock.allowsNavigation('https://koi.example.com/'),
        isFalse,
      );
      expect(
        AvatarSource.placeholder.allowsNavigation('https://koi.example.com/'),
        isFalse,
      );
    });
  });

  test('ATC-M21-09 AvatarType: stored ids and ?model= values', () {
    expect(AvatarType.female.stored, 'female_human');
    expect(AvatarType.female.model, 'female');
    expect(AvatarType.male.stored, 'male_human');
    expect(AvatarType.male.model, 'male');
  });

  group('ATC-M21-09 CompanionAvatar (web avatarPreference.ts BY_COMPANION)', () {
    test('aisha → female, raza → male, koi → fox with no model', () {
      expect(CompanionAvatar.aisha.avatarId, 'female_human');
      expect(CompanionAvatar.aisha.model, AvatarType.female);
      expect(CompanionAvatar.raza.avatarId, 'male_human');
      expect(CompanionAvatar.raza.model, AvatarType.male);
      expect(CompanionAvatar.koi.avatarId, 'fox');
      expect(CompanionAvatar.koi.model, isNull);
    });

    test('resolve: companion wins over a mismatched avatar', () {
      expect(
        CompanionAvatar.resolve(companion: 'aisha', avatar: 'male_human'),
        CompanionAvatar.aisha,
      );
      expect(
        CompanionAvatar.resolve(companion: 'koi', avatar: 'male_human'),
        CompanionAvatar.koi,
      );
    });

    test('resolve: avatar-only (legacy) record maps back', () {
      expect(
        CompanionAvatar.resolve(avatar: 'female_human'),
        CompanionAvatar.aisha,
      );
      expect(
        CompanionAvatar.resolve(companion: 'nope', avatar: 'male_human'),
        CompanionAvatar.raza,
      );
      expect(CompanionAvatar.resolve(avatar: 'fox'), CompanionAvatar.koi);
      expect(CompanionAvatar.resolve(), isNull);
    });
  });

  test('ATC-M21-09 AvatarType: each avatar has its own bundled image', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    expect(AvatarType.male.imageAsset, 'assets/images/Male.png');
    expect(AvatarType.female.imageAsset, 'assets/images/Female.png');
    for (final avatar in AvatarType.values) {
      // Declared in pubspec.yaml and present: the bundle can load it.
      final data = await rootBundle.load(avatar.imageAsset);
      final bytes = data.buffer.asUint8List();
      expect(bytes.sublist(1, 4), 'PNG'.codeUnits, reason: avatar.name);
      // IHDR width/height (big-endian) at bytes 16–23: 491×525.
      final header = ByteData.sublistView(bytes, 16, 24);
      expect(
        (header.getUint32(0), header.getUint32(4)),
        (491, 525),
        reason: avatar.name,
      );
    }
  });
}
