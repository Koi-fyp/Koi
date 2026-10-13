import 'package:flutter/material.dart';

import '../theme/koi_colors.dart';
import '../theme/koi_text.dart';

/// Shared pieces of the onboarding steps in
/// repos/koi-backend/nextjs_app/src/components/onboarding/.
///
/// Conventions for every onboarding file: 1rem = 16px; `letterSpacing: 0`
/// wherever the web sets none (CSS `normal`), so the Material theme's 0.25
/// letter-spacing does not leak in.

/// Text in the display face (var(--font-display) = Bricolage Grotesque).
TextStyle displayText(
  double size, {
  FontWeight weight = FontWeight.w700,
  Color color = KoiColors.neoBlack,
  double letterSpacing = 0,
  double? height,
}) => KoiText.display(
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: letterSpacing,
  height: height,
);

/// Text in the body face (var(--font-body) = DM Sans). DM Sans is loaded
/// 300–700 on web, so heavier Tailwind weights (font-black) render as 700.
TextStyle bodyText(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = KoiColors.neoBlack,
  double letterSpacing = 0,
  double? height,
}) => KoiText.body(
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: letterSpacing,
  height: height,
);

/// The step wrapper used by Privacy/AIDisclosure/Avatar/Language/
/// Notification: `display:flex; flex-direction:column; flex:1;
/// padding:1.5rem; max-width:480px; margin:0 auto; width:100%`, a growing
/// content area, then the full-width button with `marginTop`.
class StepLayout extends StatelessWidget {
  const StepLayout({
    super.key,
    required this.children,
    required this.button,
    required this.buttonGap,
    this.contentBottomPadding = 0,
  });

  final List<Widget> children;
  final Widget button;

  /// The button's inline `marginTop`.
  final double buttonGap;

  /// Privacy/AIDisclosure content `paddingBottom: '1rem'`.
  final double contentBottomPadding;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(bottom: contentBottomPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children,
                ),
              ),
            ),
            SizedBox(height: buttonGap),
            button,
          ],
        ),
      ),
    ),
  );
}

/// Step `<h2>`: display 800, 2rem, letter-spacing -0.03em, #000.
class StepTitle extends StatelessWidget {
  const StepTitle(this.text, {super.key, required this.bottom});
  final String text;

  /// The h2's `marginBottom`.
  final double bottom;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: bottom),
    child: Text(
      text,
      style: displayText(
        32,
        weight: FontWeight.w800,
        letterSpacing: -0.03 * 32,
      ),
    ),
  );
}

/// Step subtitle `<p>`: body, #777, 0.9rem.
class StepSubtitle extends StatelessWidget {
  const StepSubtitle(this.text, {super.key, required this.bottom});
  final String text;
  final double bottom;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: bottom),
    child: Text(text, style: bodyText(14.4, color: const Color(0xFF777777))),
  );
}

/// The selectable option tiles in AvatarStep/LanguageStep:
/// borderRadius 12px; border selected ? 2.5px #000 : 2px #ddd;
/// background selected ? [selectedColor] : #fff; boxShadow selected ?
/// 4px 4px 0 0 #000 : none; transform selected ? translate(-2px,-2px);
/// transition all 0.1s ease.
class OptionTile extends StatelessWidget {
  const OptionTile({
    super.key,
    required this.selected,
    required this.selectedColor,
    required this.padding,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final Color selectedColor;
  final EdgeInsetsGeometry padding;
  final VoidCallback onTap;
  final Widget child;

  static const Color idleBorder = Color(0xFFDDDDDD);

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        curve: Curves.ease,
        transform: Matrix4.translationValues(
          selected ? -2 : 0,
          selected ? -2 : 0,
          0,
        ),
        padding: padding,
        decoration: BoxDecoration(
          color: selected ? selectedColor : KoiColors.neoWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? KoiColors.neoBlack : idleBorder,
            width: selected ? 2.5 : 2,
          ),
          boxShadow: selected
              ? const [BoxShadow(offset: Offset(4, 4))]
              : const [],
        ),
        child: child,
      ),
    ),
  );
}
