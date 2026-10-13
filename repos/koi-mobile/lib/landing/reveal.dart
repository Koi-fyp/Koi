import 'dart:async';

import 'package:flutter/widgets.dart';

/// globals.css `.reveal` / `.reveal.visible`, driven like page.tsx's
/// IntersectionObserver (threshold 0.12): once at least 12% of the child is
/// inside the viewport it fades in from translateY(28px) over 0.6s ease, after
/// an optional `transitionDelay`. It never hides again (web only adds the
/// class).
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.threshold = Reveal.defaultThreshold,
    this.duration = Reveal.defaultDuration,
    this.curve = Curves.ease,
  });

  final Widget child;
  final Duration delay;

  /// IntersectionObserver threshold (about/page.tsx 0.12, how-it-works 0.1,
  /// about TeamCards 0.15).
  final double threshold;

  /// Transition length (.reveal 0.6s; TeamCards 0.5s).
  final Duration duration;

  /// Transition timing (.reveal ease; TeamCards' transform uses
  /// cubic-bezier(0.34,1.2,0.64,1)).
  final Curve curve;

  static const Duration defaultDuration = Duration(milliseconds: 600);
  static const double fromDy = 28;
  static const double defaultThreshold = 0.12;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> {
  bool _visible = false;
  ScrollPosition? _position;
  Timer? _delay;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _position?.removeListener(_check);
    _position = Scrollable.maybeOf(context)?.position;
    _position?.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (!mounted || _visible || _delay != null) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.height == 0) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final viewport = MediaQuery.sizeOf(context).height;
    final shown =
        (top + box.size.height).clamp(0, viewport) - top.clamp(0, viewport);
    if (shown >= widget.threshold * box.size.height) {
      _position?.removeListener(_check);
      _delay = Timer(widget.delay, () {
        if (mounted) setState(() => _visible = true);
      });
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_check);
    _delay?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: _visible ? 1 : 0,
    duration: widget.duration,
    curve: Curves.ease, // opacity is always ease on web
    child: AnimatedContainer(
      duration: widget.duration,
      curve: widget.curve,
      transform: Matrix4.translationValues(0, _visible ? 0 : Reveal.fromDy, 0),
      child: widget.child,
    ),
  );
}
