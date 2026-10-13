import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../onboarding/step_layout.dart';
import '../theme/koi_colors.dart';
import 'widgets/chat_widgets.dart';

/// Mirrors repos/koi-backend/nextjs_app/src/app/(authenticated)/chat/page.tsx
/// at phone width (`flex-col-reverse`): the avatar panel sits on top and is
/// shown only before the first message (`hidden sm:flex` once there are
/// messages), the chat column (OfflineBanner, MessageList, InputBar) below.
///
/// The "thinking bubbles" only render while typing, which on a phone is
/// always after the first message, when the panel is already hidden, so
/// they are never visible at this width and are not built.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final FocusNode _input = FocusNode();
  bool _mounted = false; // page.tsx `mounted` (drives the entry animation)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _mounted = true);
    });
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(authServiceProvider.select((a) => a.user?.uid));
    if (uid == null) return const SizedBox.shrink();
    final chat = ref.watch(chatControllerProvider(uid));
    final hasMessages = chat.messages.isNotEmpty;

    return ColoredBox(
      color: KoiColors.background,
      child: Column(
        children: [
          if (!hasMessages)
            _AvatarPanel(mounted: _mounted, onCta: () => _input.requestFocus()),
          Expanded(
            child: Column(
              children: [
                const _OfflineBannerHost(),
                Expanded(
                  child: MessageList(
                    messages: chat.messages,
                    isTyping: chat.isTyping,
                  ),
                ),
                InputBar(
                  onSend: chat.send,
                  disabled: chat.isTyping,
                  focusNode: _input,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows [OfflineBanner] while the device is offline (web: navigator.onLine
/// + online/offline events; mobile: connectivity_plus).
class _OfflineBannerHost extends ConsumerWidget {
  const _OfflineBannerHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(onlineProvider).valueOrNull ?? true;
    return online ? const SizedBox.shrink() : const OfflineBanner();
  }
}

/// The avatar panel: `width:100%; max-width:340px; padding:16px 16px 16px 0;
/// flex-col gap-3` with the yellow Male.png card and the CTA.
class _AvatarPanel extends StatelessWidget {
  const _AvatarPanel({required this.mounted, required this.onCta});
  final bool mounted;
  final VoidCallback onCta;

  // transition: opacity/transform 0.8s cubic-bezier(0.34, 1.56, 0.64, 1)
  static const Curve springy = Cubic(0.34, 1.56, 0.64, 1);

  @override
  Widget build(BuildContext context) {
    final maxCardHeight = MediaQuery.sizeOf(context).height * 0.8; // 80vh
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Entrance(
                visible: mounted,
                dy: 20,
                duration: const Duration(milliseconds: 800),
                curve: springy,
                child: Center(
                  child: Container(
                    key: const Key('avatar-card'),
                    constraints: BoxConstraints(
                      maxWidth: 340,
                      maxHeight: maxCardHeight,
                    ),
                    clipBehavior: Clip.antiAlias,
                    // rounded-[1.5rem] border-[3px] border-black
                    // bg-[#FFD100] shadow-[6px_6px_0_0_#000]
                    decoration: BoxDecoration(
                      color: KoiColors.neoYellow,
                      border: Border.all(width: 3),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [BoxShadow(offset: Offset(6, 6))],
                    ),
                    child: Image.asset(
                      'assets/images/Male.png', // public/Male.png
                      semanticLabel: 'KOI companion',
                      fit: BoxFit.contain,
                      width: double.infinity,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12), // gap-3
              _Entrance(
                visible: mounted,
                dy: 10,
                delay: const Duration(milliseconds: 300), // transitionDelay
                duration: const Duration(milliseconds: 100),
                curve: Curves.ease,
                child: _CtaButton(onTap: onCta),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fades/slides a child in once [visible] turns true (CSS transitions on
/// opacity + translateY, with optional transition-delay).
class _Entrance extends StatefulWidget {
  const _Entrance({
    required this.visible,
    required this.dy,
    required this.duration,
    required this.curve,
    required this.child,
    this.delay = Duration.zero,
  });

  final bool visible;
  final double dy;
  final Duration duration;
  final Duration delay;
  final Curve curve;
  final Widget child;

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance> {
  bool _shown = false;
  Timer? _timer;

  @override
  void didUpdateWidget(_Entrance old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  void _sync() {
    if (widget.visible && !_shown && _timer == null) {
      _timer = Timer(widget.delay, () {
        if (mounted) setState(() => _shown = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: _shown ? 1 : 0),
    duration: widget.duration,
    curve: widget.curve,
    builder: (_, t, child) => Opacity(
      opacity: t.clamp(0, 1),
      child: Transform.translate(
        offset: Offset(0, widget.dy * (1 - t)),
        child: child,
      ),
    ),
    child: widget.child,
  );
}

/// "Try other avatars too!" — white pill, 2.5px border, 4px shadow, display
/// 700 0.88rem; mousedown translate(2px,2px) + 2px shadow. Web focuses the
/// message input when tapped.
class _CtaButton extends StatefulWidget {
  const _CtaButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_CtaButton> createState() => _CtaButtonState();
}

class _CtaButtonState extends State<_CtaButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: const Key('avatar-cta'),
    onTapDown: (_) => setState(() => _pressed = true),
    onTapUp: (_) => setState(() => _pressed = false),
    onTapCancel: () => setState(() => _pressed = false),
    onTap: widget.onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      curve: Curves.ease,
      transform: Matrix4.translationValues(
        _pressed ? 2 : 0,
        _pressed ? 2 : 0,
        0,
      ),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      decoration: BoxDecoration(
        color: KoiColors.neoWhite,
        border: Border.all(width: 2.5),
        borderRadius: BorderRadius.circular(9999),
        boxShadow: [
          BoxShadow(offset: _pressed ? const Offset(2, 2) : const Offset(4, 4)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          StrokeIcon(
            paths: mailIconPaths,
            size: 16,
            strokeWidth: 2,
            color: KoiColors.neoBlack,
          ),
          const SizedBox(width: 8),
          Text(
            'Try other avatars too!',
            softWrap: false,
            style: displayText(14.08),
          ),
        ],
      ),
    ),
  );
}
