import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../avatar/avatar_call_screen.dart';
import '../avatar/avatar_providers.dart';
import '../avatar/avatar_view.dart' show AvatarImage, AvatarType;
import '../avatar/call_icons.dart';
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
    final avatar = ref.watch(selectedAvatarProvider);

    return ColoredBox(
      color: KoiColors.background,
      child: CustomMultiChildLayout(
        delegate: _ChatLayout(),
        children: [
          LayoutId(
            id: _Slot.panel,
            child: hasMessages
                ? const SizedBox.shrink()
                : _AvatarPanel(
                    mounted: _mounted,
                    avatar: avatar,
                    onCta: _focusInput,
                  ),
          ),
          LayoutId(id: _Slot.banner, child: const _OfflineBannerHost()),
          LayoutId(
            id: _Slot.list,
            child: MessageList(
              messages: chat.messages,
              isTyping: chat.isTyping,
            ),
          ),
          LayoutId(
            id: _Slot.input,
            child: InputBar(
              onSend: chat.send,
              disabled: chat.isTyping,
              focusNode: _input,
              leading: const _CallEntryButton(),
            ),
          ),
        ],
      ),
    );
  }

  /// Web: `inputRef.current?.focus()`. On Android, focusing a field that is
  /// already focused (keyboard dismissed with Back) does not bring the
  /// keyboard back, so ask for it explicitly in that case.
  void _focusInput() {
    if (_input.hasFocus) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    } else {
      _input.requestFocus();
    }
  }
}

enum _Slot { panel, banner, list, input }

/// Web stacks the panel above the chat column in a fixed-height,
/// `overflow: hidden` box where the panel never shrinks, so on a short
/// screen (e.g. 360x800dp with the keyboard open) the chat column is
/// squeezed out. Mobile-only adaptation: the input bar and banner always get
/// their natural height, the message list keeps at least [minList], and the
/// avatar panel gets what is left (its card shrinks, or the whole panel
/// hides when even a small card no longer fits; see [_AvatarPanel]).
class _ChatLayout extends MultiChildLayoutDelegate {
  _ChatLayout();

  static const double minList = 120;

  @override
  void performLayout(Size size) {
    final w = size.width;
    final loose = BoxConstraints(maxWidth: w, maxHeight: size.height);
    final input = layoutChild(_Slot.input, loose).height;
    final banner = layoutChild(_Slot.banner, loose).height;
    final rest = (size.height - input - banner).clamp(0.0, size.height);
    final panel = layoutChild(
      _Slot.panel,
      BoxConstraints(maxWidth: w, maxHeight: (rest - minList).clamp(0.0, rest)),
    ).height;
    final list = (rest - panel).clamp(0.0, rest);
    layoutChild(_Slot.list, BoxConstraints.tightFor(width: w, height: list));

    positionChild(_Slot.panel, Offset.zero);
    positionChild(_Slot.banner, Offset(0, panel));
    positionChild(_Slot.list, Offset(0, panel + banner));
    positionChild(_Slot.input, Offset(0, panel + banner + list));
  }

  @override
  bool shouldRelayout(_ChatLayout oldDelegate) => false;
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
///
/// Mobile-only: when [_ChatLayout] gives it less than its natural height
/// the card shrinks (keeping Male.png's aspect ratio instead of web's
/// overflow clip); below [minCard] the whole panel hides, e.g. while the
/// keyboard is open on a 360x800dp phone.
class _AvatarPanel extends StatelessWidget {
  const _AvatarPanel({
    required this.mounted,
    required this.avatar,
    required this.onCta,
  });
  final bool mounted;

  /// The selected avatar's image (Settings "Avatar").
  final AvatarType avatar;
  final VoidCallback onCta;

  // transition: opacity/transform 0.8s cubic-bezier(0.34, 1.56, 0.64, 1)
  static const Curve springy = Cubic(0.34, 1.56, 0.64, 1);

  static const double minCard = 120;
  static const double _padY = 16 + 16, _gap = 12; // padding, gap-3
  static const double _imageAspect = 491 / 525; // assets/images/Male.png

  @override
  Widget build(BuildContext context) {
    final maxCardHeight = MediaQuery.sizeOf(context).height * 0.8; // 80vh
    final ctaHeight = _CtaButton.heightFor(MediaQuery.textScalerOf(context));
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxHeight < _padY + minCard + _gap + ctaHeight) {
          return const SizedBox.shrink();
        }
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
                  Flexible(
                    child: _Entrance(
                      visible: mounted,
                      dy: 20,
                      duration: const Duration(milliseconds: 800),
                      curve: springy,
                      child: Center(
                        heightFactor: 1,
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
                          child: AspectRatio(
                            aspectRatio: _imageAspect,
                            // public/Male.png (female: same image for now)
                            child: AvatarImage(avatar),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: _gap),
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
      },
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
/// message input when tapped (chat/page.tsx:155,
/// `onClick={() => inputRef.current?.focus()}`); it opens no avatar picker
/// or Settings despite the label. Mobile mirrors that (decision 2026-10-13),
/// so nothing visible happens if the keyboard is already open. Reported in
/// WEB_BUGS_FOUND_DURING_MOBILE.md.
class _CtaButton extends StatefulWidget {
  const _CtaButton({required this.onTap});
  final VoidCallback onTap;

  static TextStyle get _style => displayText(14.08);

  /// Laid-out height: padding 14*2 + border 2.5*2 + the taller of the 16px
  /// icon and the single (softWrap: false) text line.
  static double heightFor(TextScaler scaler) {
    final line = TextPainter(
      text: TextSpan(text: 'Try other avatars too!', style: _style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final h = line.height;
    line.dispose();
    return 28 + 5 + (h > 16 ? h : 16);
  }

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
            style: _CtaButton._style,
          ),
        ],
      ),
    ),
  );
}

/// Mobile-only (Prompt 10): opens the avatar call screen. Round like the
/// InputBar send button (48dp so it reads as a separate control), white
/// like the CTA pill.
class _CallEntryButton extends StatelessWidget {
  const _CallEntryButton();

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Start avatar call',
    excludeSemantics: true,
    child: GestureDetector(
      key: const Key('avatar-call-entry'),
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const AvatarCallScreen())),
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: KoiColors.neoWhite,
          shape: BoxShape.circle,
          border: Border.all(width: 2.5),
          boxShadow: const [BoxShadow(offset: Offset(3, 3))],
        ),
        child: StrokeIcon(
          paths: videoIconPaths,
          size: 20,
          strokeWidth: 2.2,
          color: KoiColors.neoBlack,
        ),
      ),
    ),
  );
}
