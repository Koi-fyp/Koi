import 'dart:async';

import 'package:flutter/material.dart';

import '../../chat/widgets/chat_widgets.dart' show StrokeIcon;
import '../../onboarding/step_layout.dart' show bodyText;
import '../../shell/svg_path.dart';
import '../../theme/koi_colors.dart';
import '../../theme/koi_shadows.dart';

/// Shared pieces of repos/koi-backend/nextjs_app/src/app/(authenticated)/
/// settings/ (page.tsx and components/).
///
/// Conventions: 1rem = 16px. Tailwind 3.4 preflight is on (globals.css
/// `@tailwind base`), so plain text uses body DM Sans with line-height 1.5,
/// `<button>` inherits the body font, and `<ul>` has `list-style: none`
/// (web shows NO bullet markers, only the inline padding-left). DM Sans is
/// loaded 300–700, so fontWeight 800/900 render as 700 (see bodyText).
/// Web hover effects have no touch equivalent and are not mirrored.

/// CSS `line-height` default from preflight (`html { line-height: 1.5 }`).
const double kPreflightLineHeight = 1.5;

/// `<p>` / `<span>` in the settings pages: body face, preflight line-height.
TextStyle settingsText(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = KoiColors.neoBlack,
  double? height = kPreflightLineHeight,
  double letterSpacing = 0,
}) => bodyText(
  size,
  weight: weight,
  color: color,
  height: height,
  letterSpacing: letterSpacing,
);

/// page.tsx `DIVIDER`: height 1px, background #f0f0f0.
class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key});
  @override
  Widget build(BuildContext context) =>
      const SizedBox(height: 1, child: ColoredBox(color: Color(0xFFF0F0F0)));
}

/// page.tsx section label `<p>`: weight 800, 0.7rem, #bbb, letter-spacing
/// 0.1em, uppercase, margin-bottom 0.5rem, padding-left 2px.
class SettingsSectionLabel extends StatelessWidget {
  const SettingsSectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 2, bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: settingsText(
        11.2,
        weight: FontWeight.w800,
        color: const Color(0xFFBBBBBB),
        letterSpacing: 0.1 * 11.2,
      ),
    ),
  );
}

/// page.tsx `.settings-card`: border 2.5px #000, radius 1.25rem, box-shadow
/// 4px 4px 0 0 #000, margin-bottom 1.25rem (About & Help: 1.5rem).
class SettingsCard extends StatelessWidget {
  const SettingsCard({
    super.key,
    required this.child,
    this.color = KoiColors.neoWhite,
    this.padding = const EdgeInsets.symmetric(horizontal: 16), // 0 1rem
    this.bottom = 20,
  });

  final Widget child;
  final Color color;
  final EdgeInsets padding;
  final double bottom;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: bottom),
    child: Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(width: 2.5),
        borderRadius: BorderRadius.circular(20),
        boxShadow: KoiShadows.hard(4),
      ),
      child: child,
    ),
  );
}

/// The 38px rounded icon tile shared by SettingsRow and the About & Help
/// rows: 38x38, radius 8px, border 2px #000, font-size 1.1rem.
class SettingsIconTile extends StatelessWidget {
  const SettingsIconTile(
    this.icon, {
    super.key,
    this.color = KoiColors.neoGray, // var(--neo-gray)
  });
  final String icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 38,
    height: 38,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      border: Border.all(width: 2),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(icon, style: const TextStyle(fontSize: 17.6, height: 1)),
  );
}

/// Label (700, 0.9rem) + description (0.78rem, #999, margin-top 1px).
class SettingsRowText extends StatelessWidget {
  const SettingsRowText({
    super.key,
    required this.label,
    required this.desc,
    this.labelColor = KoiColors.neoBlack,
  });
  final String label;
  final String desc;
  final Color labelColor;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: settingsText(14.4, weight: FontWeight.w700, color: labelColor),
      ),
      const SizedBox(height: 1),
      Text(desc, style: settingsText(12.48, color: const Color(0xFF999999))),
    ],
  );
}

// SettingsRow.tsx chevron: path "M9 18l6-6-6-6", stroke #ccc, width 2.
final List<Path> chevronRightPaths = [parseSvgPath('M9 18l6-6-6-6')];
// page.tsx About & Help chevron: path "M6 9l6 6 6-6".
final List<Path> chevronDownPaths = [parseSvgPath('M6 9l6 6 6-6')];

/// Mirrors components/SettingsRow.tsx: full-width button, padding
/// 0.875rem 0, gap 0.875rem; icon tile, text, then a toggle or a chevron.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.label,
    required this.desc,
    this.danger = false,
    this.toggle = false,
    this.on = false,
    this.onTap,
  });

  final String icon;
  final String label;
  final String desc;
  final bool danger;
  final bool toggle;
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    toggled: toggle ? on : null,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            SettingsIconTile(icon),
            const SizedBox(width: 14),
            Expanded(
              child: SettingsRowText(
                label: label,
                desc: desc,
                // danger ? '#FF4136' : '#000'
                labelColor: danger ? KoiColors.danger : KoiColors.neoBlack,
              ),
            ),
            if (toggle)
              SettingsToggle(on: on)
            else
              StrokeIcon(
                paths: chevronRightPaths,
                size: 18,
                strokeWidth: 2,
                color: const Color(0xFFCCCCCC),
              ),
          ],
        ),
      ),
    ),
  );
}

/// SettingsRow.tsx toggle: 44x24, radius 12px, border 2px #000, background
/// on ? var(--neo-blue) : #ddd; knob 16x16 white, border 1.5px #000, at
/// top 2px, left on ? 20px : 2px (inside the border), transition 300ms.
class SettingsToggle extends StatelessWidget {
  const SettingsToggle({super.key, required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 200), // duration-200
    width: 44,
    height: 24,
    decoration: BoxDecoration(
      color: on ? KoiColors.neoBlue : const Color(0xFFDDDDDD),
      border: Border.all(width: 2),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Stack(
      children: [
        AnimatedPositioned(
          duration: const Duration(milliseconds: 300), // duration-300
          top: 2,
          left: on ? 20 : 2,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: KoiColors.neoWhite,
              border: Border.all(width: 1.5),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    ),
  );
}

/// components/Toast.tsx `type`.
enum ToastType { success, error, info }

/// One toast request. [seq] changes on every new request so the timer
/// restarts (web: setToast replaces the message and resets the timeout).
@immutable
class ToastMessage {
  const ToastMessage(this.message, this.type, this.seq);
  final String message;
  final ToastType type;
  final int seq;
}

/// Mirrors components/Toast.tsx: fixed bottom 5rem, centred; closes after
/// `duration` (3000ms); slideUp 0.3s cubic-bezier(0.34, 1.56, 0.64, 1).
class SettingsToast extends StatefulWidget {
  const SettingsToast({
    super.key,
    required this.toast,
    required this.onClose,
    this.duration = const Duration(milliseconds: 3000),
  });

  final ToastMessage toast;
  final VoidCallback onClose;
  final Duration duration;

  // bgColors / icons in Toast.tsx
  static const Map<ToastType, Color> bgColors = {
    ToastType.success: Color(0xFF2DD36F),
    ToastType.error: Color(0xFFFF4136),
    ToastType.info: Color(0xFF2D63EB),
  };
  static const Map<ToastType, String> icons = {
    ToastType.success: '✓',
    ToastType.error: '✗',
    ToastType.info: 'ℹ',
  };

  @override
  State<SettingsToast> createState() => _SettingsToastState();
}

class _SettingsToastState extends State<SettingsToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  )..forward();
  Timer? _timer;

  static const Curve _curve = Cubic(0.34, 1.56, 0.64, 1);

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(SettingsToast old) {
    super.didUpdateWidget(old);
    if (old.toast.seq != widget.toast.seq) _restart();
  }

  void _restart() {
    _timer?.cancel();
    _timer = Timer(widget.duration, widget.onClose);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.toast.type;
    final bg = SettingsToast.bgColors[type]!;
    final success = type == ToastType.success;
    final width = MediaQuery.sizeOf(context).width;
    return AnimatedBuilder(
      animation: _in,
      builder: (context, child) {
        final t = _in.value;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            // from translateY(20px) to 0, overshooting like the bezier
            offset: Offset(0, 20 * (1 - _curve.transform(t))),
            child: child,
          ),
        );
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 0.9 * width), // 90vw
        child: Container(
          key: const Key('settings-toast'),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(width: 2.5),
            borderRadius: BorderRadius.circular(12),
            boxShadow: KoiShadows.hard(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: success ? KoiColors.neoBlack : KoiColors.neoWhite,
                ),
                child: Text(
                  SettingsToast.icons[type]!,
                  style: settingsText(
                    16,
                    weight: FontWeight.w900,
                    height: 1,
                    color: success ? const Color(0xFF2DD36F) : bg,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  widget.toast.message,
                  style: settingsText(
                    14.4,
                    weight: FontWeight.w700,
                    color: success ? KoiColors.neoBlack : KoiColors.neoWhite,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Places a [SettingsToast] like web's `position: fixed; bottom: 5rem;
/// left: 50%; translateX(-50%)`, above the system navigation bar.
class SettingsToastLayer extends StatelessWidget {
  const SettingsToastLayer({super.key, this.toast, required this.onClose});
  final ToastMessage? toast;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = toast;
    if (t == null) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      right: 0,
      bottom: 80 + MediaQuery.viewPaddingOf(context).bottom,
      child: Center(
        child: SettingsToast(toast: t, onClose: onClose),
      ),
    );
  }
}

// BackButton.tsx arrow: path "M15 18l-6-6 6-6", stroke #000, width 2.5.
final List<Path> backArrowPaths = [parseSvgPath('M15 18l-6-6 6-6')];

/// Mirrors components/BackButton.tsx ("Back to Settings", router.back()).
/// padding 0.625rem 1rem, white, border 2.5px, radius 12px, shadow 3px,
/// 700 0.9rem, gap 0.5rem, margin-bottom 1.5rem; mousedown → translateY(1px)
/// + 1px shadow.
class BackToSettingsButton extends StatefulWidget {
  const BackToSettingsButton({super.key, this.onTap});

  /// Defaults to Navigator.maybePop (web router.back()).
  final VoidCallback? onTap;

  @override
  State<BackToSettingsButton> createState() => _BackToSettingsButtonState();
}

class _BackToSettingsButtonState extends State<BackToSettingsButton> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        child: GestureDetector(
          key: const Key('back-to-settings'),
          onTapDown: (_) => _set(true),
          onTapUp: (_) => _set(false),
          onTapCancel: () => _set(false),
          onTap: widget.onTap ?? () => Navigator.of(context).maybePop(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150), // all 0.15s ease
            curve: Curves.ease,
            transform: Matrix4.translationValues(0, _down ? 1 : 0, 0),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            decoration: BoxDecoration(
              color: KoiColors.neoWhite,
              border: Border.all(width: 2.5),
              borderRadius: BorderRadius.circular(12),
              boxShadow: KoiShadows.hard(_down ? 1 : 3),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StrokeIcon(
                  paths: backArrowPaths,
                  size: 16,
                  strokeWidth: 2.5,
                  color: KoiColors.neoBlack,
                ),
                const SizedBox(width: 8),
                Text(
                  'Back to Settings',
                  style: settingsText(14.4, weight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// A `<ul>` under preflight: no markers, `padding-left` only.
class SettingsPlainList extends StatelessWidget {
  const SettingsPlainList({
    super.key,
    required this.items,
    required this.style,
    this.paddingLeft = 20, // 1.25rem
    this.itemGap = 0,
  });

  final List<String> items;
  final TextStyle style;
  final double paddingLeft;
  final double itemGap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(left: paddingLeft),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom: i < items.length - 1 ? itemGap : 0,
            ),
            child: Text(items[i], style: style),
          ),
      ],
    ),
  );
}

/// CSS `linear-gradient(135deg, a 0%, b 100%)`. Flutter's top-left to
/// bottom-right gradient matches CSS 135deg exactly only for square boxes;
/// for other shapes the colour stops sit slightly differently.
LinearGradient cssGradient135(List<Color> colors, [List<double>? stops]) =>
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: colors,
      stops: stops,
    );

/// NeoButton label that scales down when the button is narrower than the
/// text. Web keeps `.neo-btn-*` text full size (`white-space: nowrap`) and
/// lets it overflow the button at phone width; mobile scales it instead,
/// like the nav pills (Prompt 4). Must be the NeoButton's direct child.
class FitButtonLabel extends StatelessWidget {
  const FitButtonLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Flexible(
    child: FittedBox(fit: BoxFit.scaleDown, child: Text(text, softWrap: false)),
  );
}
