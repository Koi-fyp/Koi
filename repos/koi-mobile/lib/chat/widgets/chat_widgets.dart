import 'package:flutter/material.dart';

import '../../onboarding/step_layout.dart';
import '../../shell/svg_path.dart';
import '../../theme/koi_colors.dart';
import '../chat_controller.dart';

// Chat UI, mirroring repos/koi-backend/nextjs_app/src/components/chat/* and
// app/(authenticated)/chat/page.tsx (OfflineBanner). 1rem = 16px; Tailwind
// v3.4.19 defaults (text-sm .875rem/1.25rem, leading-6 1.5rem, text-4xl
// 2.25rem/2.5rem, leading-tight 1.25, tracking-tighter -0.05em, text-base
// 1rem/1.5rem, leading-relaxed 1.625, gray-600 #4b5563, gray-400 #9ca3af);
// text without a font class is body DM Sans (font-black → 700).

/// A stroked SVG icon (viewBox 0 0 24 24, round caps/joins).
class StrokeIcon extends StatelessWidget {
  const StrokeIcon({
    super.key,
    required this.paths,
    required this.size,
    required this.color,
    required this.strokeWidth,
  });

  final List<Path> paths;
  final double size;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _StrokePainter(paths, color, strokeWidth)),
  );
}

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.paths, this.color, this.strokeWidth);
  final List<Path> paths;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final path in paths) {
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_StrokePainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}

// InputBar.tsx send icon
final List<Path> sendIconPaths = [
  parseSvgPath('M22 2L11 13'),
  parseSvgPath('M22 2L15 22 11 13 2 9l20-7z'),
];

// chat/page.tsx "Try other avatars too!" icon
final List<Path> mailIconPaths = [
  parseSvgPath(
    'M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z',
  ),
  parseSvgPolyline('22,6 12,13 2,6'),
];

/// chat/page.tsx OfflineBanner (shown only when offline).
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  static const String text =
      'You’re offline — your message will send when reconnected';

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true, // role="alert"
    child: Container(
      key: const Key('offline-banner'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 16),
      decoration: const BoxDecoration(
        color: KoiColors.neoYellow,
        border: Border(bottom: BorderSide(width: 2)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: displayText(12.8, letterSpacing: 0.03 * 12.8),
      ),
    ),
  );
}

/// HeroText.tsx (phone width: text-center, text-4xl).
class HeroText extends StatelessWidget {
  const HeroText({super.key});

  @override
  Widget build(BuildContext context) {
    final h1 = bodyText(
      36,
      weight: FontWeight.w700,
      letterSpacing: -0.05 * 36,
      height: 1.25,
    );
    // px-3 py-1 inline-block highlight spans
    Widget chip(String t, Color bg) => Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Text(t, style: h1.copyWith(color: KoiColors.neoWhite)),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 768), // max-w-3xl
      child: Column(
        children: [
          Text.rich(
            textAlign: TextAlign.center,
            TextSpan(
              style: h1,
              children: [
                const TextSpan(text: "I'm "),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: chip('Koi', const Color(0xFF3B82F6)),
                ),
                const TextSpan(text: ', How can I '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: chip('Help You', const Color(0xFFFF4A60)),
                ),
                const TextSpan(text: '?'),
              ],
            ),
          ),
          const SizedBox(height: 20), // mt-5
          Text(
            "A calm place to think out loud, sort through what's heavy, and "
            'get a reply that actually feels present.',
            textAlign: TextAlign.center,
            style: bodyText(16, color: const Color(0xFF393939), height: 1.625),
          ),
        ],
      ),
    );
  }
}

/// `koiSlideIn 0.25s cubic-bezier(0.34,1.56,0.64,1) both`:
/// from opacity 0, translateY(8px) scale(0.97).
class _SlideIn extends StatelessWidget {
  const _SlideIn({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 250),
    curve: const Cubic(0.34, 1.56, 0.64, 1),
    builder: (_, t, child) => Opacity(
      opacity: t.clamp(0, 1),
      child: Transform.translate(
        offset: Offset(0, 8 * (1 - t)),
        child: Transform.scale(scale: 0.97 + 0.03 * t, child: child),
      ),
    ),
    child: child,
  );
}

/// The round "K" avatar (MessageBubble / TypingIndicator).
class _KAvatar extends StatelessWidget {
  const _KAvatar({required this.style});
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: KoiColors.neoBlue,
      shape: BoxShape.circle,
      border: Border.all(width: 2.5),
    ),
    child: Text('K', style: style),
  );
}

/// `toLocaleTimeString([], {hour:'2-digit', minute:'2-digit'})`, following
/// the phone's 12/24-hour setting.
String formatTime(DateTime t, {required bool use24h}) {
  String two(int v) => v.toString().padLeft(2, '0');
  if (use24h) return '${two(t.hour)}:${two(t.minute)}';
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '${two(h)}:${two(t.minute)} ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// MessageBubble.tsx.
class MessageBubble extends StatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.showAvatar = false,
  });
  final ChatMessage message;
  final bool showAvatar;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final isUser = m.isUser;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.82 - 32;

    final bubble = AnimatedContainer(
      // whileTap: user x/y 5px; both scale 0.995
      duration: const Duration(milliseconds: 100),
      transform: _pressed
          ? (Matrix4.translationValues(isUser ? 5 : 0, isUser ? 5 : 0, 0)
              ..scaleByDouble(0.995, 0.995, 1, 1))
          : Matrix4.identity(),
      padding: const EdgeInsets.all(12), // p-3
      decoration: BoxDecoration(
        // user: bg-[#3B82F6] hard-shadow; ai: glass-white hard-shadow-cyan
        color: isUser ? const Color(0xFF3B82F6) : const Color(0xCCFFFFFF),
        border: Border.all(width: 2),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: isUser ? KoiColors.neoBlack : KoiColors.cyan,
            offset: const Offset(5, 5),
          ),
        ],
      ),
      child: Text(
        m.content,
        style: bodyText(
          14,
          color: isUser ? KoiColors.neoWhite : KoiColors.neoBlack,
          height: 24 / 14,
        ),
      ),
    );

    return _SlideIn(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          key: Key('bubble-${m.sender}'),
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!isUser) ...[
                    SizedBox.square(
                      dimension: 36,
                      child: widget.showAvatar
                          ? _KAvatar(
                              style: bodyText(
                                16,
                                weight: FontWeight.w700,
                                color: KoiColors.neoWhite,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 8), // gap-2
                  ],
                  Flexible(
                    child: GestureDetector(
                      onTapDown: (_) => setState(() => _pressed = true),
                      onTapUp: (_) => setState(() => _pressed = false),
                      onTapCancel: () => setState(() => _pressed = false),
                      child: bubble,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.only(
                top: 8,
                left: isUser ? 0 : 4,
                right: isUser ? 4 : 0,
              ),
              child: Text(
                formatTime(
                  m.timestamp,
                  use24h: MediaQuery.alwaysUse24HourFormatOf(context),
                ),
                style: bodyText(11, color: const Color(0xFF4B5563)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// TypingIndicator.tsx.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  // neoDot 1.4s ease-in-out infinite, delays 0 / 0.18s / 0.36s
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  /// @keyframes neoDot: 0%,80%,100% scale .55 opacity .3; 40% scale 1
  /// opacity 1 (ease-in-out per segment).
  static double _wave(double p) {
    double ease(double t) => Curves.easeInOut.transform(t);
    if (p < 0.4) return ease(p / 0.4);
    if (p < 0.8) return 1 - ease((p - 0.4) / 0.4);
    return 0;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    key: const Key('typing-indicator'),
    padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _KAvatar(
          style: displayText(
            14.4,
            weight: FontWeight.w800,
            color: KoiColors.neoWhite,
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: KoiColors.neoWhite,
            border: Border.all(width: 2.5),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomRight: Radius.circular(20),
              bottomLeft: Radius.circular(4),
            ),
            boxShadow: const [BoxShadow(offset: Offset(2, 2))],
          ),
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) => Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  Builder(
                    builder: (_) {
                      // Negative-delay phase shift; before the first cycle
                      // web shows the 0% frame, which equals the wave's rest.
                      final p = (_c.value - i * 0.18 / 1.4) % 1;
                      final w = _wave(p < 0 ? p + 1 : p);
                      return Opacity(
                        opacity: 0.3 + 0.7 * w,
                        child: Transform.scale(
                          scale: 0.55 + 0.45 * w,
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: KoiColors.neoBlue,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// MessageList.tsx: hero when empty, bubbles (AI avatar on the first of a
/// run of AI messages), typing indicator; scrolls to the bottom on change.
class MessageList extends StatefulWidget {
  const MessageList({
    super.key,
    required this.messages,
    required this.isTyping,
  });
  final List<ChatMessage> messages;
  final bool isTyping;

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(MessageList old) {
    super.didUpdateWidget(old);
    if (old.messages.length != widget.messages.length ||
        old.isTyping != widget.isTyping) {
      // bottomRef.scrollIntoView({ behavior: 'smooth' }); the list is
      // reversed, so the bottom is offset 0 (exact, unlike maxScrollExtent,
      // which a lazy list only estimates and can overshoot).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.ease,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final msgs = widget.messages;
    if (msgs.isEmpty && !widget.isTyping) {
      // flex 1, column, centred vertically, padding 0 1.5rem
      return Semantics(
        label: 'Conversation',
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (c.maxHeight - 24).clamp(0, double.infinity),
              ),
              child: const Center(child: HeroText()),
            ),
          ),
        ),
      );
    }
    final items = <Widget>[
      for (var i = 0; i < msgs.length; i++) ...[
        if (i > 0) const SizedBox(height: 6), // gap 6px
        MessageBubble(
          key: ValueKey(msgs[i].id),
          message: msgs[i],
          showAvatar: !msgs[i].isUser && (i == 0 || msgs[i - 1].isUser),
        ),
      ],
      if (widget.isTyping) ...[
        const SizedBox(height: 6),
        const TypingIndicator(),
      ],
    ];
    return Semantics(
      label: 'Conversation', // role="log" aria-label
      liveRegion: true,
      // Reversed + shrink-wrapped and top-aligned: a short conversation
      // still starts at the top like web, a long one stays pinned to the
      // newest message.
      child: Align(
        alignment: Alignment.topCenter,
        child: ListView(
          key: const Key('message-list'),
          controller: _scroll,
          reverse: true,
          shrinkWrap: true,
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          children: items.reversed.toList(),
        ),
      ),
    );
  }
}

/// InputBar.tsx.
class InputBar extends StatefulWidget {
  const InputBar({
    super.key,
    required this.onSend,
    this.disabled = false,
    this.focusNode,
  });

  final ValueChanged<String> onSend;
  final bool disabled;
  final FocusNode? focusNode;

  static const String placeholder = 'Type your message...';

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  final TextEditingController _text = TextEditingController();
  bool _pressed = false;

  bool get _canSend => !widget.disabled && _text.text.trim().isNotEmpty;

  void _submit() {
    final trimmed = _text.text.trim();
    if (trimmed.isEmpty || widget.disabled) return;
    widget.onSend(trimmed);
    _text.clear();
    setState(() {});
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSend = _canSend;
    return Container(
      color: KoiColors.background, // background: #ffe5d9
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
        decoration: BoxDecoration(
          color: KoiColors.neoWhite,
          border: Border.all(width: 2.5),
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [BoxShadow(offset: Offset(3, 3))],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end, // align-items flex-end
          children: [
            Expanded(
              child: ConstrainedBox(
                // minHeight 36px, maxHeight 128px (then it scrolls)
                constraints: const BoxConstraints(
                  minHeight: 36,
                  maxHeight: 128,
                ),
                child: TextField(
                  key: const Key('chat-input'),
                  controller: _text,
                  focusNode: widget.focusNode,
                  enabled: !widget.disabled,
                  minLines: 1,
                  maxLines: null,
                  // Web: Enter (without Shift) sends.
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submit(),
                  onChanged: (_) => setState(() {}),
                  style: bodyText(15, height: 1.55),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    hintText: InputBar.placeholder,
                    // Tailwind preflight textarea::placeholder: gray-400
                    hintStyle: bodyText(
                      15,
                      color: const Color(0xFF9CA3AF),
                      height: 1.55,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Semantics(
              button: true,
              enabled: canSend,
              label: 'Send message',
              child: GestureDetector(
                key: const Key('chat-send'),
                onTapDown: canSend
                    ? (_) => setState(() => _pressed = true)
                    : null,
                onTapUp: (_) => setState(() => _pressed = false),
                onTapCancel: () => setState(() => _pressed = false),
                onTap: canSend ? _submit : null,
                child: AnimatedScale(
                  scale: _pressed ? 0.92 : 1,
                  duration: const Duration(milliseconds: 100),
                  child: AnimatedContainer(
                    // transition: background 0.12s ease
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.ease,
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: canSend
                          ? KoiColors.neoBlack
                          : const Color(0xFFE0E0E0),
                      shape: BoxShape.circle,
                      border: Border.all(width: 2),
                    ),
                    child: StrokeIcon(
                      paths: sendIconPaths,
                      size: 18,
                      strokeWidth: 2.2,
                      color: canSend
                          ? KoiColors.neoWhite
                          : const Color(0xFFAAAAAA),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
