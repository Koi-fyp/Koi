import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:koi_mobile/avatar/avatar_view.dart';
import 'package:koi_mobile/avatar/avatar_web_page.dart';
import 'package:koi_mobile/avatar/local_avatar_server.dart';

/// Stands in for the WebView (which can't run in widget tests). Records
/// what the app asks of the page; the test plays the page's part.
class FakeAvatarPage implements AvatarWebPage {
  FakeAvatarPage(this.handlers);
  final AvatarWebPageHandlers handlers;

  final loads = <AvatarPageTarget>[];
  final scripts = <String>[];
  bool disposed = false;
  bool alive = true;
  int aliveChecks = 0;

  /// The page posts AVATAR_READY on KoiBridge.
  void sendReady() => handlers.onMessage(AvatarViewController.readyMessage);

  /// Only the setEmotion calls.
  List<String> get emotionCalls => scripts
      .where((s) => s.contains(AvatarViewController.setEmotionFunction))
      .toList();

  /// Only the setConversationState calls.
  List<String> get stateCalls => scripts
      .where(
        (s) => s.contains(AvatarViewController.setConversationStateFunction),
      )
      .toList();

  Uri? get lastUrl => switch (loads.lastOrNull) {
    AvatarUrlTarget(:final url) => url,
    _ => null,
  };

  @override
  Future<void> load(AvatarPageTarget target) async {
    loads.add(target);
    handlers.onPageStarted();
  }

  @override
  Future<void> runJavaScript(String source) async => scripts.add(source);

  @override
  Future<bool> isAlive() async {
    aliveChecks++;
    return alive;
  }

  @override
  Widget buildView(BuildContext context) =>
      const SizedBox.expand(key: Key('fake-webview'));

  @override
  void dispose() => disposed = true;
}

/// The page factory: keeps every page it made.
class FakeAvatarPages {
  final all = <FakeAvatarPage>[];

  AvatarWebPage create(AvatarWebPageHandlers handlers) {
    final page = FakeAvatarPage(handlers);
    all.add(page);
    return page;
  }

  List<FakeAvatarPage> get live => all.where((p) => !p.disposed).toList();
  FakeAvatarPage get last => all.last;
}

/// Stands in for the loopback server (KOI_AVATAR_URL=local): no socket,
/// just the origin it would have and whether it was closed.
class FakeLocalHost implements LocalAvatarHost {
  FakeLocalHost(this.port, {this.failStart = false});
  final int port;
  final bool failStart;
  int starts = 0;
  bool closed = false;

  @override
  Future<Uri> start() async {
    starts++;
    if (failStart) throw const SocketException('bind failed');
    return LocalAvatarServer.originFor(port);
  }

  @override
  Future<void> close() async => closed = true;
}

/// The host factory: keeps every host it made.
class FakeLocalHosts {
  FakeLocalHosts({this.failStart = false});
  final bool failStart;
  final all = <FakeLocalHost>[];

  LocalAvatarHost create() {
    final host = FakeLocalHost(40123 + all.length, failStart: failStart);
    all.add(host);
    return host;
  }

  FakeLocalHost get last => all.last;
}
