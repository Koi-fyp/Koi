import 'package:flutter/material.dart';

import '../theme/koi_colors.dart';
import '../theme/koi_shadows.dart';
import '../theme/koi_text.dart';
import 'mode_selector.dart';
import 'nav_icons.dart';

/// The signed-in tabs, from `TABS` in BottomNav.tsx.
enum KoiTab {
  chat('Chat', KoiNavGlyph.chat), // href '/chat'
  progress('Progress', KoiNavGlyph.progress), // href '/progress'
  settings('Settings', KoiNavGlyph.settings); // href '/settings'

  const KoiTab(this.label, this.glyph);
  final String label;
  final KoiNavGlyph glyph;
}

/// Mirrors repos/koi-backend/nextjs_app/src/components/layout/BottomNav.tsx
/// (named "BottomNav" on web but fixed at the top).
///
/// Phone layout = option A (approved 2026-10-13): the web's single pill needs
/// ~580dp but a 360dp phone has ~274dp inside it, so the content is split
/// into two stacked pills with identical styling, each in its own copy of the
/// web wrapper (px-4 py-2 bg-[#ffe5d9]):
///   pill 1: "K" logo + "KOI" (left) and the Mode selector (right);
///   pill 2: Chat / Progress / Settings, spread evenly.
/// Size changes vs web (tab-fit follow-up, approved 2026-10-13): pill inner
/// side padding px-6 (24) → 16 and tab side padding px-4 (16) → 8. Measured
/// with the bundled DM Sans Bold the tab row needs ~277dp; at 360dp the pill
/// now has 290dp. On phones narrower than that the tab row scales down just
/// enough to fit (never up), so it can never overflow.
///
/// Tailwind values assume 1 unit = 0.25rem = 4px and v3.4.19 defaults
/// (gray-600 #4b5563, rounded-md 0.375rem, text-sm 0.875rem/1.25rem,
/// text-lg 1.125rem/1.75rem).
class KoiTopNav extends StatelessWidget {
  const KoiTopNav({
    super.key,
    required this.current,
    required this.onSelect,
    required this.onLogoTap,
    this.background = KoiColors.background,
  });

  final KoiTab current;
  final ValueChanged<KoiTab> onSelect;

  /// Web: the logo is a Link to '/', which redirects a signed-in, onboarded
  /// user straight back to '/chat'.
  final VoidCallback onLogoTap;

  /// The strip behind the pills; the Chat tab passes its background tint
  /// (Prompt 27).
  final Color background;

  /// Mobile-only reductions of the tab `px-4` and pill `px-6` (class doc).
  static const double tabPaddingX = 8;
  static const double pillPaddingX = 16;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: background, // bg-[#ffe5d9], or the Chat tint
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _NavPill(
              key: const Key('nav-pill-brand'),
              child: Row(
                children: [
                  _Logo(onTap: onLogoTap),
                  const Spacer(),
                  const ModeSelector(),
                ],
              ),
            ),
            _NavPill(
              key: const Key('nav-pill-tabs'),
              child: _ScaleDownToFit(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final tab in KoiTab.values)
                      _TabLink(
                        tab: tab,
                        active: tab == current,
                        onTap: () => onSelect(tab),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The web wrapper + pill: `px-4 py-2` around `bg-white border-[3px]
/// border-black rounded-full shadow-[5px_5px_0px_0px_#06b6d4] px-6 py-2`
/// (px-6 → [KoiTopNav.pillPaddingX] on mobile).
class _NavPill extends StatelessWidget {
  const _NavPill({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KoiTopNav.pillPaddingX,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: KoiColors.neoWhite,
        border: Border.all(color: KoiColors.neoBlack, width: 3),
        borderRadius: BorderRadius.circular(9999),
        boxShadow: KoiShadows.hardShadowCyan, // 5px 5px 0 0 #06b6d4
      ),
      child: child,
    ),
  );
}

// No font-family on the nav: inherits body var(--font-body) = DM Sans.
// letterSpacing 0 = CSS `normal`; without it the Material theme's body
// letter-spacing (0.25) would be inherited.
TextStyle _bold(double size, double lineHeight, Color color) => KoiText.body(
  fontSize: size,
  height: lineHeight / size,
  fontWeight: FontWeight.w700,
  color: color,
  letterSpacing: 0,
);

const Color _gray600 = Color(0xFF4B5563); // Tailwind gray-600

class _Logo extends StatelessWidget {
  const _Logo({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: const Key('nav-logo'),
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // w-8 h-8 rounded-md bg-[var(--neo-blue)] border-[2px]
        // border-black font-bold text-white text-sm
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: KoiColors.neoBlue,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: KoiColors.neoBlack, width: 2),
          ),
          child: Text('K', style: _bold(14, 20, KoiColors.neoWhite)),
        ),
        const SizedBox(width: 8), // gap-2
        // font-bold text-black text-lg
        Text('KOI', style: _bold(18, 28, KoiColors.neoBlack)),
      ],
    ),
  );
}

class _TabLink extends StatelessWidget {
  const _TabLink({
    required this.tab,
    required this.active,
    required this.onTap,
  });

  final KoiTab tab;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // active: bg-black text-white border-2 border-black
    // inactive: text-gray-600 (hover:text-black has no touch equivalent)
    final color = active ? KoiColors.neoWhite : _gray600;
    return Semantics(
      selected: active,
      button: true,
      child: GestureDetector(
        key: Key('nav-tab-${tab.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          // px-4 (→ 8 on mobile) py-2 rounded-full
          padding: const EdgeInsets.symmetric(
            horizontal: KoiTopNav.tabPaddingX,
            vertical: 8,
          ),
          decoration: active
              ? BoxDecoration(
                  color: KoiColors.neoBlack,
                  border: Border.all(color: KoiColors.neoBlack, width: 2),
                  borderRadius: BorderRadius.circular(9999),
                )
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              KoiNavIcon(tab.glyph, color: color, active: active),
              const SizedBox(width: 8), // gap-2
              Text(tab.label, style: _bold(14, 20, color)), // font-bold text-sm
            ],
          ),
        ),
      ),
    );
  }
}

/// Fills the available width (so `spaceBetween` spreads the tabs) and scales
/// the child down uniformly only when it is wider than that.
class _ScaleDownToFit extends StatelessWidget {
  const _ScaleDownToFit({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => FittedBox(
      fit: BoxFit.scaleDown,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: constraints.maxWidth),
        child: child,
      ),
    ),
  );
}
