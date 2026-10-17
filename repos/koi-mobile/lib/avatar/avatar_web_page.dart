import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// What the page reports back to the avatar.
class AvatarWebPageHandlers {
  const AvatarWebPageHandlers({
    required this.onMessage,
    required this.onPageStarted,
    required this.onMainFrameError,
    required this.allowNavigation,
  });

  /// A string posted on the `KoiBridge` channel.
  final void Function(String message) onMessage;

  /// A (re)load of the page began; the old page's AvatarController is gone.
  final VoidCallback onPageStarted;

  /// The page itself (not a font or image on it) failed to load.
  final VoidCallback onMainFrameError;

  /// Whether the WebView may go to this URL.
  final bool Function(String url) allowNavigation;
}

/// What to load: the avatar host page or the bundled mock asset.
sealed class AvatarPageTarget {
  const AvatarPageTarget();
}

class AvatarUrlTarget extends AvatarPageTarget {
  const AvatarUrlTarget(this.url);
  final Uri url;
}

class AvatarAssetTarget extends AvatarPageTarget {
  const AvatarAssetTarget(this.asset);
  final String asset;
}

/// The one WebView that shows the avatar, as far as the app needs it.
/// [WebViewAvatarPage] is the real one; tests use a fake.
abstract class AvatarWebPage {
  Future<void> load(AvatarPageTarget target);
  Future<void> runJavaScript(String source);

  /// Whether the page still answers and its AvatarController exists.
  Future<bool> isAlive();
  Widget buildView(BuildContext context);

  /// Stops all callbacks; the widget tree drops the native view.
  void dispose();
}

typedef AvatarWebPageFactory = AvatarWebPage Function(
  AvatarWebPageHandlers handlers,
);

/// The JavaScript channel name (Flutter track; feat/avatar-webview-host
/// WEBVIEW_HOST.md: `window.KoiBridge?.postMessage("AVATAR_READY")`).
const String koiBridgeChannel = 'KoiBridge';

/// webview_flutter implementation. Never given tokens, cookies or user data:
/// it only loads the avatar page and runs the fixed AvatarController calls.
class WebViewAvatarPage implements AvatarWebPage {
  WebViewAvatarPage(this._handlers) {
    _controller = WebViewController(
      // No microphone/camera for the page, ever.
      onPermissionRequest: (request) => request.deny(),
    );
    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(false)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(
        koiBridgeChannel,
        onMessageReceived: (m) {
          if (!_disposed) _handlers.onMessage(m.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (_disposed || !_handlers.allowNavigation(request.url)) {
              debugPrint('KOI: avatar navigation blocked');
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (_) {
            if (!_disposed) _handlers.onPageStarted();
          },
          onWebResourceError: (error) {
            // Fonts, images etc. may fail without breaking the avatar.
            if (!_disposed && (error.isForMainFrame ?? false)) {
              _handlers.onMainFrameError();
            }
          },
          onHttpError: (error) {
            final failed = error.request?.uri.removeFragment();
            if (!_disposed && failed != null && failed == _page) {
              _handlers.onMainFrameError();
            }
          },
        ),
      );
  }

  final AvatarWebPageHandlers _handlers;
  late final WebViewController _controller;
  Uri? _page;
  bool _disposed = false;

  @override
  Future<void> load(AvatarPageTarget target) async {
    if (_disposed) return;
    try {
      switch (target) {
        case AvatarUrlTarget(:final url):
          _page = url.removeFragment();
          await _controller.loadRequest(url);
        case AvatarAssetTarget(:final asset):
          _page = null;
          await _controller.loadFlutterAsset(asset);
      }
    } catch (e) {
      debugPrint('KOI: avatar page load failed: ${e.runtimeType}');
      if (!_disposed) _handlers.onMainFrameError();
    }
  }

  @override
  Future<void> runJavaScript(String source) async {
    if (_disposed) return;
    await _controller.runJavaScript(source);
  }

  @override
  Future<bool> isAlive() async {
    if (_disposed) return false;
    try {
      final result = await _controller
          .runJavaScriptReturningResult('window.AvatarController ? 1 : 0')
          .timeout(const Duration(seconds: 2));
      return result.toString() == '1';
    } catch (_) {
      return false;
    }
  }

  @override
  Widget buildView(BuildContext context) =>
      WebViewWidget(controller: _controller);

  @override
  void dispose() => _disposed = true;
}
