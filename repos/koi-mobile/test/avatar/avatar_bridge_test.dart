import 'dart:convert';

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

    test('nothing is sent before AVATAR_READY; other messages ignored', () {
      c.beginLoad();
      c.setEmotion(AvatarEmotion.joy, 0.5);
      c.handleBridgeMessage('HELLO');
      c.handleBridgeMessage('avatar_ready');
      expect(sent, isEmpty);
      expect(c.status, AvatarStatus.loading);
    });

    test('only the latest queued emotion is sent, once, after ready', () {
      c.beginLoad();
      c.setEmotion(AvatarEmotion.joy, 0.5);
      c.setEmotion(AvatarEmotion.sorrow, 0.2);
      c.setEmotion(AvatarEmotion.angry, 0.3);
      c.handleBridgeMessage('AVATAR_READY');

      expect(c.isReady, isTrue);
      expect(sent, [
        'window.AvatarController && '
            'window.AvatarController.setEmotion("angry", 0.3);',
      ]);
      c.handleBridgeMessage('AVATAR_READY'); // duplicate: nothing more
      expect(sent, hasLength(1));

      c.setEmotion(AvatarEmotion.fun, 1);
      expect(argsOf(sent.last), ['fun', 1.0]);
      expect(sent, hasLength(2));
    });

    test('after a reload the current emotion is sent again once ready', () {
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
      ]);
    });

    test('reconnect asks the view to load the page again', () {
      c.markFailed();
      c.reconnect();
      expect(reloads, 1);
    });

    test('a detached page can no longer make the avatar ready', () {
      c.beginLoad();
      c.detachPage(token);
      c.handleBridgeMessage('AVATAR_READY');
      expect(c.isReady, isFalse);
    });

    test('a stale token cannot detach the current page', () {
      c.detachPage(Object());
      c.beginLoad();
      c.handleBridgeMessage('AVATAR_READY');
      expect(c.isReady, isTrue);
    });

    testWidgets('no AVATAR_READY within 20 s → failed; ready recovers', (
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

    test('avatar, conversation state and mouth cues are Dart state only', () {
      c.beginLoad();
      c.handleBridgeMessage('AVATAR_READY');
      sent.clear();
      c.setAvatar(AvatarType.female);
      c.setConversationState(AvatarConversationState.thinking);
      c.setMouthCues(const [MouthCue(start: 0, end: 0.2, value: 'D')]);
      expect(c.avatar, AvatarType.female);
      expect(c.conversationState, AvatarConversationState.thinking);
      expect(c.mouthCues.single.value, 'D');
      expect(sent, isEmpty);
    });
  });

  group('jsCall', () {
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
      }
    });

    test('only the fixed avatar functions can be called', () {
      expect(
        () => AvatarViewController.jsCall('alert', ['x']),
        throwsArgumentError,
      );
      expect(
        () => AvatarViewController.jsCall(
          'AvatarController.setConversationState',
          ['idle'],
        ),
        throwsArgumentError,
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

  group('sessions', () {
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
    test('KOI_AVATAR_URL: empty → placeholder, mock (debug only), https', () {
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

    test('page URL adds ?model= and keeps other query parameters', () {
      final s = AvatarSource.parse('https://koi.example.com/avatar-host?v=2#x');
      expect(
        s.pageUrl(AvatarType.female).toString(),
        'https://koi.example.com/avatar-host?v=2&model=female',
      );
      expect(s.pageUrl(AvatarType.male).queryParameters['model'], 'male');
    });

    test('navigation stays on the avatar origin', () {
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

    test('mock may only show its own asset; placeholder nothing', () {
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

  test('AvatarType: stored ids, fox/unknown → male', () {
    expect(AvatarType.fromStored('female_human'), AvatarType.female);
    expect(AvatarType.fromStored('male_human'), AvatarType.male);
    expect(AvatarType.fromStored('fox'), AvatarType.male);
    expect(AvatarType.fromStored(null), AvatarType.male);
    expect(AvatarType.female.stored, 'female_human');
    expect(AvatarType.female.model, 'female');
  });
}
