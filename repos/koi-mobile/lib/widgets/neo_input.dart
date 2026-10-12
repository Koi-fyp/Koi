import 'package:flutter/material.dart';

import '../theme/koi_colors.dart';
import '../theme/koi_radii.dart';
import '../theme/koi_shadows.dart';
import '../theme/koi_text.dart';

/// Mirrors repos/koi-backend/nextjs_app/src/components/ui/NeoInput.tsx and the
/// `.neo-input` class in src/app/globals.css.
///
/// [multiline] corresponds to the web `as="textarea"` prop.
///
/// Error border: NeoInput.tsx adds Tailwind `border-red-500` when `error` is
/// set, but in the compiled web CSS `.neo-input` (unlayered, emitted after the
/// Tailwind utilities, same specificity) re-declares `border: 2px solid #000`,
/// so the browser shows a black border. Mobile renders what the web renders:
/// black border, red error text. (Open question in the Prompt 2 report.)
class NeoInput extends StatefulWidget {
  const NeoInput({
    super.key,
    this.label,
    this.error,
    this.placeholder,
    this.controller,
    this.onChanged,
    this.multiline = false,
    this.enabled = true,
    this.obscureText = false,
    this.keyboardType,
    this.focusNode,
  });

  final String? label;
  final String? error;
  final String? placeholder;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final bool multiline;
  final bool enabled;
  final bool obscureText;
  final TextInputType? keyboardType;
  final FocusNode? focusNode;

  // globals.css .neo-input (1rem = 16px)
  static const double borderWidth = 2; // border: 2px solid #000
  static const EdgeInsets padding =
      EdgeInsets.symmetric(vertical: 12, horizontal: 16); // 0.75rem 1rem
  static const Duration transition =
      Duration(milliseconds: 150); // box-shadow/border-color 0.15s ease

  /// NeoInput.tsx wrapper `flex flex-col gap-1` → 0.25rem.
  static const double gap = 4;

  /// HTML default <textarea rows> is 2.
  static const int textareaRows = 2;

  @override
  State<NeoInput> createState() => _NeoInputState();
}

class _NeoInputState extends State<NeoInput> {
  FocusNode? _ownFocusNode;
  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownFocusNode ??= FocusNode());
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(NeoInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownFocusNode)?.removeListener(_onFocusChange);
      _focusNode.addListener(_onFocusChange);
    }
  }

  void _onFocusChange() {
    if (_focused != _focusNode.hasFocus) {
      setState(() => _focused = _focusNode.hasFocus);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _ownFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = AnimatedContainer(
      duration: NeoInput.transition,
      curve: Curves.ease,
      decoration: BoxDecoration(
        color: KoiColors.neoWhite, // background: #fff
        borderRadius: KoiRadii.inputAll, // border-radius: 0.75rem
        border: Border.all(
          width: NeoInput.borderWidth,
          // :focus { border-color: var(--neo-blue) }
          color: _focused ? KoiColors.neoBlue : KoiColors.neoBlack,
        ),
        // :focus { box-shadow: 0 0 0 3px rgba(45,99,235,0.2) }
        boxShadow: _focused ? KoiShadows.neoFocus : const [],
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        onChanged: widget.onChanged,
        enabled: widget.enabled,
        obscureText: widget.obscureText,
        keyboardType: widget.multiline
            ? TextInputType.multiline
            : widget.keyboardType,
        minLines: widget.multiline ? NeoInput.textareaRows : 1,
        maxLines: widget.multiline ? null : 1,
        // font-family body, font-size 1rem, color #000
        style: KoiText.body(fontSize: 16, color: KoiColors.neoBlack),
        // caret-color: auto → currentColor (#000)
        cursorColor: KoiColors.neoBlack,
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: NeoInput.padding,
          hintText: widget.placeholder,
          // ::placeholder { color: #aaa; font-weight: 400 }
          hintStyle: KoiText.body(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: KoiColors.inputPlaceholder,
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label?.isNotEmpty ?? false) ...[ // JS `label &&`
          // NeoInput.tsx label: display, 700, 0.875rem, #000
          Text(
            widget.label!,
            style: KoiText.display(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: KoiColors.neoBlack,
            ),
          ),
          const SizedBox(height: NeoInput.gap),
        ],
        field,
        if (widget.error?.isNotEmpty ?? false) ...[ // JS `error &&`
          const SizedBox(height: NeoInput.gap),
          // NeoInput.tsx error: body, 0.75rem, #FF4136, 500
          Text(
            widget.error!,
            style: KoiText.body(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: KoiColors.danger,
            ),
          ),
        ],
      ],
    );
  }
}
