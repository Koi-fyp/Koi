import 'package:flutter/widgets.dart';
import 'package:koi_mobile/avatar/avatar_view.dart';
import 'package:koi_mobile/avatar/avatar_web_page.dart';

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
