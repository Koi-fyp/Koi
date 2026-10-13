import 'dart:async';

import 'package:flutter/widgets.dart';

/// globals.css `.reveal` / `.reveal.visible`, driven like page.tsx's
/// IntersectionObserver (threshold 0.12): once at least 12% of the child is
/// inside the viewport it fades in from translateY(28px) over 0.6s ease, after
/// an optional `transitionDelay`. It never hides again (web only adds the
/// class).
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  static const Duration duration = Duration(milliseconds: 600);
  static const double fromDy = 28;
  static const double threshold = 0.12;

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
    if (shown >= Reveal.threshold * box.size.height) {
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
    duration: Reveal.duration,
    curve: Curves.ease,
    child: AnimatedContainer(
      duration: Reveal.duration,
      curve: Curves.ease,
      transform: Matrix4.translationValues(0, _visible ? 0 : Reveal.fromDy, 0),
      child: widget.child,
    ),
  );
}
