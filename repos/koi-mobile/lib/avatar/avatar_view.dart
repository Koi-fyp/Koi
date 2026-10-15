import 'package:flutter/material.dart';

import '../onboarding/step_layout.dart';
import '../theme/koi_colors.dart';
import '../widgets/neo_button.dart';

/// The avatar's expressions (docs set; the Flutter track bridge protocol
/// `AvatarController.setEmotion('<emotion>', <intensity>)`).
///
/// Not the same thing as `Emotion` in core/emotion.dart, which is the
/// user-emotion label stored with messages.
enum AvatarEmotion { neutral, joy, angry, sorrow, fun }

/// loading → ready (later: the `AVATAR_READY` message on the `KoiBridge`
/// channel); failed when the avatar can't load (later: a WebView load
/// error), back to loading on [AvatarViewController.reconnect].
enum AvatarStatus { loading, ready, failed }

/// Everything the rest of the app may ask of the avatar. [AvatarView] is
/// the only thing that reads it, so a WebView can replace the placeholder
/// inside [AvatarView] without touching any caller.
class AvatarViewController extends ChangeNotifier {
  AvatarEmotion _emotion = AvatarEmotion.neutral;
  double _intensity = 0;
  AvatarStatus _status = AvatarStatus.loading;

  AvatarEmotion get emotion => _emotion;

  /// 0.0 to 1.0.
  double get intensity => _intensity;
  AvatarStatus get status => _status;
  bool get isReady => _status == AvatarStatus.ready;

  /// Later: `runJavaScript("AvatarController.setEmotion('$emotion',
  /// $intensity)")`. [intensity] is clamped to 0.0–1.0.
  void setEmotion(AvatarEmotion emotion, double intensity) {
    if (intensity.isNaN) {
      throw ArgumentError.value(intensity, 'intensity', 'must be a number');
    }
    final clamped = intensity.clamp(0.0, 1.0);
    if (emotion == _emotion && clamped == _intensity) return;
    _emotion = emotion;
    _intensity = clamped;
    notifyListeners();
  }

  /// Called by [AvatarView]'s inside once the avatar can be shown.
  void markReady() => _set(AvatarStatus.ready);

  /// Called by [AvatarView]'s inside when the avatar can't load; shows the
  /// fallback (static Male.png + Reconnect).
  void markFailed() => _set(AvatarStatus.failed);

  /// The fallback's Reconnect button: load the avatar again.
  void reconnect() => _set(AvatarStatus.loading);

  void _set(AvatarStatus s) {
    if (s == _status) return;
    _status = s;
    notifyListeners();
  }
}

/// The avatar area. For now a placeholder (Male.png + the current emotion);
/// later a `webview_flutter` WebView on the Next.js /companion-scene route.
class AvatarView extends StatefulWidget {
  const AvatarView({
    super.key,
    required this.controller,
    required this.onReady,
    this.onFailed,
  });

  final AvatarViewController controller;

  /// Fired each time the avatar becomes ready (placeholder: right after it
  /// is first shown, and after a Reconnect).
  final VoidCallback onReady;

  /// Fired when the avatar can't load and the fallback is shown.
  final VoidCallback? onFailed;

  static const String reconnectLabel = 'Reconnect';
  static const String unavailableText = 'Avatar couldn’t load';

  @override
  State<AvatarView> createState() => _AvatarViewState();
}

class _AvatarViewState extends State<AvatarView> {
  late AvatarStatus _last = widget.controller.status;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    if (_last == AvatarStatus.ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onReady();
      });
    }
    _loadIfNeeded();
  }

  @override
  void didUpdateWidget(AvatarView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _last = widget.controller.status;
      _loadIfNeeded();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  /// Placeholder "load": nothing to fetch, so it is ready on the next frame.
  /// (The WebView version loads the page here and waits for AVATAR_READY.)
  void _loadIfNeeded() {
    if (widget.controller.status != AvatarStatus.loading) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.controller.status == AvatarStatus.loading) {
        widget.controller.markReady();
      }
    });
  }

  void _changed() {
    final status = widget.controller.status;
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
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Container(
      key: const Key('avatar-view'),
      clipBehavior: Clip.antiAlias,
      // The chat avatar card: rounded-[1.5rem] border-[3px] border-black
      // bg-[#FFD100] shadow-[6px_6px_0_0_#000] (chat/page.tsx).
      decoration: BoxDecoration(
        color: c.status == AvatarStatus.failed
            ? KoiColors.neoGray
            : KoiColors.neoYellow,
        border: Border.all(width: 3),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(offset: Offset(6, 6))],
      ),
      child: c.status == AvatarStatus.failed
          ? _Fallback(onReconnect: c.reconnect)
          : _Placeholder(emotion: c.emotion),
    );
  }
}

const String _maleImage = 'assets/images/Male.png'; // public/Male.png

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.emotion});
  final AvatarEmotion emotion;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(
        _maleImage,
        key: const Key('avatar-placeholder'),
        semanticLabel: 'KOI companion',
        fit: BoxFit.contain,
      ),
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

/// Shown when the avatar can't load: the static Male.png + Reconnect
/// (Flutter track: native fallback instead of a blank WebView).
class _Fallback extends StatelessWidget {
  const _Fallback({required this.onReconnect});
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
                child: Opacity(
                  opacity: 0.5,
                  child: Image.asset(
                    _maleImage,
                    semanticLabel: 'KOI companion',
                    fit: BoxFit.contain,
                  ),
                ),
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
