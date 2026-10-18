import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../onboarding/step_layout.dart';
import '../theme/koi_colors.dart';
import '../widgets/neo_button.dart';
import 'avatar_source.dart';
import 'avatar_state.dart';
import 'avatar_web_page.dart';
import 'local_avatar_server.dart';

export 'avatar_state.dart';

/// loading → ready (`AVATAR_READY` on the `KoiBridge` channel; the
/// placeholder is ready at once); failed on a page load error or no
/// AVATAR_READY within [AvatarViewController.readyTimeout]; back to loading
/// on [AvatarViewController.reconnect] or when the page reloads itself.
enum AvatarStatus { loading, ready, failed }

/// The Flutter → avatar bridge, and everything the rest of the app may ask
/// of the avatar. [AvatarView] is the only thing that drives it, so the
/// placeholder and the WebView look the same to callers.
///
/// Web contract: feat/avatar-webview-host
/// src/components/avatar/WEBVIEW_HOST.md. Nothing is sent before
/// AVATAR_READY; only the latest emotion and conversation state are kept
/// and sent once ready, and again after every reload.
///
/// - emotion: `AvatarController.setEmotion(emotion, intensity)`.
/// - conversation state: `AvatarController.setConversationState(state)`,
///   'idle' | 'listening' | 'thinking' | 'speaking' (approved by Fatima).
/// - avatar model: no JS method; the host only reads `?model=male|female`
///   from its URL (applied through [AvatarSource.pageUrl], with a reload).
/// - TODO(fatima): lip-sync is a Dart hook only ([setMouthCues]); the
///   audio/mouth-cue bridge is not finalized, so no JavaScript is run.
/// - `AvatarController.reset()` exists on the host; not used.
class AvatarViewController extends ChangeNotifier {
  AvatarViewController({this.readyTimeout = defaultReadyTimeout});

  static const Duration defaultReadyTimeout = Duration(seconds: 20);

  /// The only message the host posts on `KoiBridge`.
  static const String readyMessage = 'AVATAR_READY';

  static const String setEmotionFunction = 'AvatarController.setEmotion';
  static const String setConversationStateFunction =
      'AvatarController.setConversationState';
  static const Set<String> _jsFunctions = {
    setEmotionFunction,
    setConversationStateFunction,
  };

  /// A call to one of the host's fixed functions; every argument goes
  /// through [jsonEncode], never pasted into the source as-is.
  static String jsCall(String function, List<Object?> args) {
    if (!_jsFunctions.contains(function)) {
      throw ArgumentError.value(function, 'function', 'not an avatar call');
    }
    final encoded = args.map(jsonEncode).join(', ');
    return 'window.AvatarController && window.$function($encoded);';
  }

  final Duration readyTimeout;

  AvatarEmotion _emotion = AvatarEmotion.neutral;
  double _intensity = 0;
  AvatarStatus _status = AvatarStatus.loading;
  AvatarType _avatar = AvatarType.male;
  AvatarConversationState _conversation = AvatarConversationState.idle;
  List<MouthCue> _mouthCues = const [];
  String? _sessionId;

  Object? _pageToken;
  Future<void> Function(String js)? _run;
  VoidCallback? _reload;
  Timer? _timeout;
  bool _disposed = false;

  AvatarEmotion get emotion => _emotion;

  /// 0.0 to 1.0.
  double get intensity => _intensity;
  AvatarStatus get status => _status;
  bool get isReady => _status == AvatarStatus.ready;
  AvatarType get avatar => _avatar;
  AvatarConversationState get conversationState => _conversation;
  List<MouthCue> get mouthCues => _mouthCues;

  /// The conversation whose updates are applied; others are dropped.
  String? get sessionId => _sessionId;

  /// `AvatarController.setEmotion(emotion, intensity)` once the avatar is
  /// ready; until then only the latest value is kept. [intensity] is
  /// clamped to 0.0–1.0.
  void setEmotion(AvatarEmotion emotion, double intensity) {
    if (intensity.isNaN) {
      throw ArgumentError.value(intensity, 'intensity', 'must be a number');
    }
    final clamped = intensity.clamp(0.0, 1.0).toDouble();
    if (emotion == _emotion && clamped == _intensity) return;
    _emotion = emotion;
    _intensity = clamped;
    _notify();
    _sendEmotion();
  }

  /// Dart state only (see the TODO above). For a remote host [AvatarView]
  /// reloads the page with the new `?model=`.
  void setAvatar(AvatarType avatar) {
    if (avatar == _avatar) return;
    _avatar = avatar;
    _notify();
  }

  /// `AvatarController.setConversationState(state)` once the avatar is
  /// ready; until then only the latest value is kept.
  void setConversationState(AvatarConversationState state) {
    if (state == _conversation) return;
    _conversation = state;
    _notify();
    _sendConversationState();
  }

  /// Dart state only (see the lip-sync TODO above).
  void setMouthCues(List<MouthCue> cues) {
    _mouthCues = List.unmodifiable(cues);
    _notify();
  }

  /// A new conversation: from now on only updates for [id] apply.
  void beginSession(String id) => _sessionId = id;

  /// Applies a conversation-state event. Returns false (and changes
  /// nothing) for an update from another session.
  bool apply(AvatarStateEvent event) {
    switch (event) {
      case AvatarSessionStarted(:final sessionId):
        beginSession(sessionId);
        return true;
      case AvatarStateUpdate():
        if (event.sessionId != _sessionId) return false;
        final emotion = event.emotion;
        if (emotion != null && !event.intensity.isNaN) {
          setEmotion(emotion, event.intensity);
        }
        final state = event.conversationState;
        if (state != null) setConversationState(state);
        return true;
    }
  }

  // ── Driven by AvatarView ──────────────────────────────────────────────

  /// A WebView page now backs the avatar. [run] runs JavaScript in it,
  /// [reload] loads it again.
  void attachPage(
    Object token, {
    required Future<void> Function(String js) run,
    required VoidCallback reload,
  }) {
    _pageToken = token;
    _run = run;
    _reload = reload;
  }

  /// The page [token] is gone; its late messages are ignored.
  void detachPage(Object token) {
    if (_pageToken != token) return;
    _pageToken = null;
    _run = null;
    _reload = null;
    _timeout?.cancel();
  }

  /// A page (re)load started: not ready until the next AVATAR_READY, which
  /// must come within [readyTimeout].
  void beginLoad() {
    _timeout?.cancel();
    _timeout = Timer(readyTimeout, () {
      if (_status == AvatarStatus.loading) {
        debugPrint('KOI: avatar not ready after ${readyTimeout.inSeconds}s');
        markFailed();
      }
    });
    _set(AvatarStatus.loading);
  }

  /// A message on the `KoiBridge` channel.
  void handleBridgeMessage(String message) {
    if (_run == null || isReady) return;
    if (message == readyMessage) markReady();
  }

  /// The avatar can be shown; sends the current emotion and conversation
  /// state.
  void markReady() {
    _timeout?.cancel();
    _set(AvatarStatus.ready);
    _sendEmotion();
    _sendConversationState();
  }

  /// The avatar can't load; shows the fallback (image + Reconnect).
  void markFailed() {
    _timeout?.cancel();
    _set(AvatarStatus.failed);
  }

  /// The fallback's Reconnect button: load the avatar again.
  void reconnect() {
    final reload = _reload;
    if (reload != null) {
      reload();
    } else {
      _set(AvatarStatus.loading);
    }
  }

  void _sendEmotion() => _send(setEmotionFunction, [_emotion.name, _intensity]);

  void _sendConversationState() =>
      _send(setConversationStateFunction, [_conversation.name]);

  /// Runs [function] in the page, only while it is ready.
  void _send(String function, List<Object?> args) {
    final run = _run;
    if (run == null || !isReady) return;
    final js = jsCall(function, args);
    try {
      run(js).catchError((Object e) {
        debugPrint('KOI: avatar $function failed: ${e.runtimeType}');
      });
    } catch (e) {
      debugPrint('KOI: avatar $function failed: ${e.runtimeType}');
    }
  }

  void _set(AvatarStatus s) {
    if (s == _status) return;
    _status = s;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timeout?.cancel();
    _run = null;
    _reload = null;
    super.dispose();
  }
}

/// The avatar area: the selected avatar's image (no KOI_AVATAR_URL) or the
/// avatar host page in a WebView, with a loading state and the native
/// fallback.
class AvatarView extends StatefulWidget {
  const AvatarView({
    super.key,
    required this.controller,
    required this.onReady,
    this.onFailed,
    this.source = AvatarSource.placeholder,
    this.pageFactory = WebViewAvatarPage.new,
    this.localHostFactory = LocalAvatarServer.new,
  });

  final AvatarViewController controller;

  /// Fired each time the avatar becomes ready.
  final VoidCallback onReady;

  /// Fired when the avatar can't load and the fallback is shown.
  final VoidCallback? onFailed;

  final AvatarSource source;

  /// Makes the WebView page (tests pass a fake).
  final AvatarWebPageFactory pageFactory;

  /// Serves the bundled page for [AvatarSource.local] (tests pass a fake).
  final LocalAvatarHostFactory localHostFactory;

  static const String reconnectLabel = 'Reconnect';
  static const String unavailableText = 'Avatar couldn’t load';
  static const String loadingText = 'Loading avatar…';

  @override
  State<AvatarView> createState() => _AvatarViewState();
}

class _AvatarViewState extends State<AvatarView> with WidgetsBindingObserver {
  late AvatarStatus _last;
  AvatarWebPage? _page;
  Object? _pageToken;
  AvatarType? _loadedAvatar;

  /// The local server and its origin, for [AvatarSource.local] only; lives
  /// as long as the page.
  LocalAvatarHost? _host;
  Uri? _localOrigin;

  /// Counts page loads, so a slow server start can't load a stale page.
  int _loads = 0;

  AvatarViewController get _c => widget.controller;
  bool get _web => widget.source.usesWebView;

  @override
  void initState() {
    super.initState();
    if (_web) {
      _openPage();
      WidgetsBinding.instance.addObserver(this);
    } else if (_c.status == AvatarStatus.ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onReady();
      });
    }
    _last = _c.status;
    _c.addListener(_changed);
    _loadIfNeeded();
  }

  @override
  void didUpdateWidget(AvatarView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller || old.source != widget.source) {
      old.controller.removeListener(_changed);
      _closePage(old.controller);
      if (_web) _openPage();
      _last = _c.status;
      _c.addListener(_changed);
      _loadIfNeeded();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c.removeListener(_changed);
    _closePage(_c);
    super.dispose();
  }

  // ── WebView ───────────────────────────────────────────────────────────

  void _openPage() {
    final token = Object();
    bool current() => mounted && _pageToken == token;
    final page = widget.pageFactory(
      AvatarWebPageHandlers(
        onMessage: (m) {
          if (current()) _c.handleBridgeMessage(m);
        },
        onPageStarted: () {
          if (current()) _c.beginLoad();
        },
        onMainFrameError: () {
          if (current()) _c.markFailed();
        },
        allowNavigation: (url) =>
            current() &&
            widget.source.allowsNavigation(url, localOrigin: _localOrigin),
      ),
    );
    _page = page;
    _pageToken = token;
    if (widget.source.kind == AvatarSourceKind.local) {
      _host = widget.localHostFactory();
    }
    _c.attachPage(token, run: page.runJavaScript, reload: _loadPage);
    // After this frame: loading notifies listeners, which must not happen
    // while the tree is building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageToken == token) _loadPage();
    });
  }

  void _closePage(AvatarViewController controller) {
    final token = _pageToken;
    if (token != null) controller.detachPage(token);
    _page?.dispose();
    _page = null;
    _pageToken = null;
    final host = _host;
    _host = null;
    _localOrigin = null;
    host?.close().catchError((Object e) {
      debugPrint('KOI: avatar server not closed: ${e.runtimeType}');
    });
  }

  void _loadPage() {
    final page = _page;
    if (page == null) return;
    final avatar = _loadedAvatar = _c.avatar;
    _loads++;
    _c.beginLoad();
    switch (widget.source.kind) {
      case AvatarSourceKind.remote:
        page.load(AvatarUrlTarget(widget.source.pageUrl(avatar)));
      case AvatarSourceKind.local:
        _loadLocal(page, avatar);
      case _:
        page.load(const AvatarAssetTarget(AvatarSource.mockAsset));
    }
  }

  /// Starts the local server (once per page), then loads the bundled page
  /// for [avatar]. A server that can't start shows the fallback.
  Future<void> _loadLocal(AvatarWebPage page, AvatarType avatar) async {
    final token = _pageToken;
    final load = _loads;
    final host = _host;
    if (host == null) return;
    bool current() => mounted && _pageToken == token && _loads == load;
    final Uri origin;
    try {
      origin = await host.start();
    } catch (e) {
      debugPrint('KOI: avatar server not started: ${e.runtimeType}');
      if (current()) _c.markFailed();
      return;
    }
    // A newer load (other model, Reconnect) or End call got here first.
    if (!current()) return;
    _localOrigin = origin;
    await page.load(AvatarUrlTarget(AvatarSource.localPageUrl(origin, avatar)));
  }

  /// Back from the background: if the page was lost, load it again (the
  /// emotion and conversation state are re-sent on AVATAR_READY).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final page = _page;
    final token = _pageToken;
    if (page == null || !_c.isReady) return;
    page.isAlive().then((alive) {
      if (!alive && mounted && _pageToken == token) {
        debugPrint('KOI: avatar page lost, reloading');
        _loadPage();
      }
    });
  }

  // ── Placeholder ───────────────────────────────────────────────────────

  /// Placeholder "load": nothing to fetch, so it is ready on the next frame.
  void _loadIfNeeded() {
    if (_web || _c.status != AvatarStatus.loading) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _c.status == AvatarStatus.loading) _c.markReady();
    });
  }

  void _changed() {
    final status = _c.status;
    if (status != _last) {
      _last = status;
      switch (status) {
        case AvatarStatus.ready:
          widget.onReady();
        case AvatarStatus.failed:
          widget.onFailed?.call();
        case AvatarStatus.loading:
          _loadIfNeeded();
      }
    }
    // The host picks the model from its URL only.
    if ((widget.source.kind == AvatarSourceKind.remote ||
            widget.source.kind == AvatarSourceKind.local) &&
        _page != null &&
        _loadedAvatar != _c.avatar) {
      _loadPage();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final failed = _c.status == AvatarStatus.failed;
    final page = _page;
    return Container(
      key: const Key('avatar-view'),
      clipBehavior: Clip.antiAlias,
      // The chat avatar card: rounded-[1.5rem] border-[3px] border-black
      // bg-[#FFD100] shadow-[6px_6px_0_0_#000] (chat/page.tsx).
      decoration: BoxDecoration(
        color: failed ? KoiColors.neoGray : KoiColors.neoYellow,
        border: Border.all(width: 3),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(offset: Offset(6, 6))],
      ),
      child: page == null
          ? (failed
                ? _Fallback(avatar: _c.avatar, onReconnect: _c.reconnect)
                : _Placeholder(avatar: _c.avatar, emotion: _c.emotion))
          : Stack(
              fit: StackFit.expand,
              children: [
                // Stays mounted under the overlays so the page keeps
                // loading (and stays loaded).
                KeyedSubtree(
                  key: const Key('avatar-webview'),
                  child: page.buildView(context),
                ),
                if (_c.status == AvatarStatus.loading)
                  _Loading(avatar: _c.avatar),
                if (failed)
                  ColoredBox(
                    color: KoiColors.neoGray,
                    child: _Fallback(
                      avatar: _c.avatar,
                      onReconnect: _c.reconnect,
                    ),
                  ),
              ],
            ),
    );
  }
}

/// The selected avatar's still image (Chat card, call placeholder,
/// loading state, fallback).
class AvatarImage extends StatelessWidget {
  const AvatarImage(this.avatar, {super.key, this.imageKey});
  final AvatarType avatar;
  final Key? imageKey;

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: ValueKey('avatar-image-${avatar.name}'),
    child: Image.asset(
      avatar.imageAsset,
      key: imageKey,
      semanticLabel: 'KOI companion',
      fit: BoxFit.contain,
    ),
  );
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.avatar, required this.emotion});
  final AvatarType avatar;
  final AvatarEmotion emotion;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      AvatarImage(avatar, imageKey: const Key('avatar-placeholder')),
      Positioned(
        left: 12,
        bottom: 12,
        child: Semantics(
          label: 'Avatar emotion: ${emotion.name}',
          excludeSemantics: true,
          child: Container(
            key: const Key('avatar-emotion-label'),
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
            decoration: BoxDecoration(
              color: KoiColors.neoWhite,
              border: Border.all(width: 2),
              borderRadius: BorderRadius.circular(9999),
              boxShadow: const [BoxShadow(offset: Offset(2, 2))],
            ),
            child: Text(emotion.name, style: displayText(12.8)),
          ),
        ),
      ),
    ],
  );
}

/// While the WebView page loads: the selected avatar, faded, and a spinner.
class _Loading extends StatelessWidget {
  const _Loading({required this.avatar});
  final AvatarType avatar;

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const Key('avatar-loading'),
    color: KoiColors.neoYellow,
    child: Stack(
      fit: StackFit.expand,
      children: [
        Opacity(opacity: 0.5, child: AvatarImage(avatar)),
        Center(
          child: Semantics(
            label: AvatarView.loadingText,
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
              decoration: BoxDecoration(
                color: KoiColors.neoWhite,
                border: Border.all(width: 2),
                borderRadius: BorderRadius.circular(9999),
                boxShadow: const [BoxShadow(offset: Offset(2, 2))],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: KoiColors.neoBlack,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(AvatarView.loadingText, style: displayText(12.8)),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Shown when the avatar can't load: the selected avatar's still image +
/// Reconnect (Flutter track: native fallback instead of a blank WebView).
class _Fallback extends StatelessWidget {
  const _Fallback({required this.avatar, required this.onReconnect});
  final AvatarType avatar;
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    final button = NeoButton(
      key: const Key('avatar-reconnect'),
      onPressed: onReconnect,
      child: const Text(AvatarView.reconnectLabel),
    );
    return LayoutBuilder(
      key: const Key('avatar-fallback'),
      builder: (context, c) {
        // Too short for the picture (keyboard open on a small phone): keep
        // just the button, scaled down if needed.
        if (c.maxHeight < 180) {
          return Center(
            child: FittedBox(fit: BoxFit.scaleDown, child: button),
          );
        }
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: Opacity(opacity: 0.5, child: AvatarImage(avatar)),
              ),
              const SizedBox(height: 8),
              Text(
                AvatarView.unavailableText,
                textAlign: TextAlign.center,
                style: displayText(14.4),
              ),
              const SizedBox(height: 12),
              button,
            ],
          ),
        );
      },
    );
  }
}
