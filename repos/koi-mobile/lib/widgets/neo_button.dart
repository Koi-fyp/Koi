import 'package:flutter/material.dart';

import '../theme/koi_colors.dart';
import '../theme/koi_shadows.dart';
import '../theme/koi_text.dart';
import 'neo_spinner.dart';
import 'outer_shadow.dart';

/// Mirrors src/components/ui/NeoButton.tsx: variant 'primary' | 'secondary' |
/// 'ghost' | 'danger'.
enum NeoButtonVariant { primary, secondary, ghost, danger }

/// Mirrors repos/koi-backend/nextjs_app/src/components/ui/NeoButton.tsx and
/// the `.neo-btn-*` classes in src/app/globals.css.
///
/// Web hover (translateY(-2px) + bigger shadow) has no touch equivalent and is
/// not used. The web `:active` state is used as the pressed state.
class NeoButton extends StatefulWidget {
  const NeoButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.variant = NeoButtonVariant.primary,
    this.loading = false,
    this.fullWidth = false,
    this.customPadding,
    this.customFontSize,
  });

  final Widget child;

  /// null = disabled (web `disabled`).
  final VoidCallback? onPressed;
  final NeoButtonVariant variant;

  /// NeoButton.tsx: disables the button and shows spinner + "Loading…".
  final bool loading;

  /// NeoButton.tsx `fullWidth` → `w-full`.
  final bool fullWidth;

  /// Per-use inline `style={{ padding }}` override (default [NeoButton.padding]).
  final EdgeInsetsGeometry? customPadding;

  /// Per-use inline `style={{ fontSize }}` override (default 1rem = 16).
  final double? customFontSize;

  /// NeoButton.tsx loading label (U+2026 ellipsis, as in the web source).
  static const String loadingLabel = 'Loading…';

  // globals.css shared .neo-btn-* rules (1rem = 16px)
  static const double borderWidth = 2.5; // border: 2.5px solid #000
  static const EdgeInsets padding = EdgeInsets.symmetric(
    vertical: 14,
    horizontal: 28,
  ); // 0.875rem 1.75rem
  static const double gap = 8; // gap: 0.5rem
  static const Duration transition = Duration(
    milliseconds: 100,
  ); // transform/box-shadow 0.1s ease
  static const double disabledOpacity = 0.5; // :disabled { opacity: 0.5 }
  static const double pressedDy = 2; // :active translateY(2px)

  @override
  State<NeoButton> createState() => _NeoButtonState();
}

/// Per-variant values from globals.css.
@immutable
class _VariantStyle {
  const _VariantStyle(
    this.background,
    this.foreground,
    this.shadow,
    this.pressedShadow,
  );

  final Color background;
  final Color foreground;
  final double shadow; // box-shadow Npx Npx 0 0 #000
  final double pressedShadow; // :active box-shadow
}

const Map<NeoButtonVariant, _VariantStyle> _styles = {
  // .neo-btn-primary: var(--neo-blue), #fff, 4px; :active 2px
  NeoButtonVariant.primary: _VariantStyle(
    KoiColors.neoBlue,
    KoiColors.neoWhite,
    4,
    2,
  ),
  // .neo-btn-secondary: var(--neo-yellow), #000, 4px; :active 2px
  NeoButtonVariant.secondary: _VariantStyle(
    KoiColors.neoYellow,
    KoiColors.neoBlack,
    4,
    2,
  ),
  // .neo-btn-ghost: transparent, #000, 3px; :active 1px
  NeoButtonVariant.ghost: _VariantStyle(
    Color(0x00000000),
    KoiColors.neoBlack,
    3,
    1,
  ),
  // .neo-btn-danger: #FF4136, #fff, 4px; :active 2px
  NeoButtonVariant.danger: _VariantStyle(
    KoiColors.danger,
    KoiColors.neoWhite,
    4,
    2,
  ),
};

class _NeoButtonState extends State<NeoButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final style = _styles[widget.variant]!;
    final pressed = _pressed && _enabled;

    // font-family display, weight 700, size 1rem; white-space: nowrap
    final textStyle = KoiText.display(
      fontSize: widget.customFontSize ?? 16,
      fontWeight: FontWeight.w700,
      color: style.foreground,
    );

    final content = widget.loading
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              NeoSpinner(color: style.foreground),
              const SizedBox(width: NeoButton.gap),
              const Text(NeoButton.loadingLabel, softWrap: false),
            ],
          )
        : widget.child;

    // A see-through fill (ghost) must not show its own shadow through it;
    // see OuterStadiumShadowPainter.
    final transparent = style.background.a < 1;

    final button = AnimatedContainer(
      duration: NeoButton.transition,
      curve: Curves.ease,
      transform: Matrix4.translationValues(
        0,
        pressed ? NeoButton.pressedDy : 0,
        0,
      ),
      width: widget.fullWidth ? double.infinity : null,
      // transition: box-shadow 0.1s ease
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: pressed ? style.pressedShadow : style.shadow),
        duration: NeoButton.transition,
        curve: Curves.ease,
        builder: (context, px, child) => CustomPaint(
          painter: transparent
              ? OuterStadiumShadowPainter(
                  color: KoiColors.neoBlack,
                  offset: Offset(px, px),
                )
              : null,
          child: Container(
            padding: widget.customPadding ?? NeoButton.padding,
            decoration: ShapeDecoration(
              color: style.background,
              shape: const StadiumBorder(
                side: BorderSide(width: NeoButton.borderWidth),
              ),
              shadows: transparent ? null : KoiShadows.hard(px),
            ),
            child: child,
          ),
        ),
        child: _content(style, textStyle, content),
      ),
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      child: Opacity(
        opacity: _enabled ? 1 : NeoButton.disabledOpacity,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _enabled ? (_) => _setPressed(true) : null,
          onTapUp: _enabled ? (_) => _setPressed(false) : null,
          onTapCancel: _enabled ? () => _setPressed(false) : null,
          onTap: _enabled ? widget.onPressed : null,
          child: button,
        ),
      ),
    );
  }

  Widget _content(_VariantStyle style, TextStyle textStyle, Widget content) =>
      DefaultTextStyle(
        style: textStyle,
        softWrap: false,
        child: IconTheme(
          data: IconThemeData(color: style.foreground),
          child: Row(
            mainAxisSize: widget.fullWidth
                ? MainAxisSize.max
                : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [content],
          ),
        ),
      );
}
