import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart' show authServiceProvider;
import '../modes/input_mode.dart';
import '../theme/koi_colors.dart';
import '../theme/koi_shadows.dart';
import '../theme/koi_text.dart';
import 'nav_icons.dart';

/// The input mode menu (Prompt 29): the top nav and the call screen's top
/// bar. Mirrors repos/koi-backend/nextjs_app/src/components/layout/
/// ModeSelector.tsx (web reference branch origin/avatar/vrm-emotion):
/// the four modes, the selected one on slate-200, a tap selects and closes.
///
/// Mobile differences:
/// - labels are Prompt 29's ("Text", "Voice", "Camera view", "Camera view +
///   voice"); web's per-item hints are not shown;
/// - the button shows the mode only: web hides its "Mode: " prefix below
///   the `sm` breakpoint (`hidden sm:inline`), i.e. on every phone;
///   screen readers still hear "Mode: …";
/// - web opens on click and closes on mouseleave; mobile closes on a tap
///   outside the menu; web's whileHover is dropped, whileTap (x/y 5px) is
///   the pressed state;
/// - Koi's fox chats by text only: the other three are disabled (the old
///   locked look without the badge) and [foxNote] is shown.
///
/// Tailwind values assume 1 unit = 0.25rem = 4px and the Tailwind v3.4.19
/// default palette (gray-300 #d1d5db, slate-200 #e2e8f0), checked against
/// tailwindcss@3.4.19 lib/public/colors.js and stubs/config.full.js.
class ModeSelector extends ConsumerStatefulWidget {
  const ModeSelector({super.key});

  static const String foxNote = 'Koi (fox) chats by text only.';

  /// `w-64`.
  static const double menuWidth = 256;

  static const Duration menuDuration = Duration(
    milliseconds: 200,
  ); // duration: 0.2

  @override
  ConsumerState<ModeSelector> createState() => _ModeSelectorState();
}

class _ModeSelectorState extends ConsumerState<ModeSelector>
    with SingleTickerProviderStateMixin {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();
  late final AnimationController _menu = AnimationController(
    vsync: this,
    duration: ModeSelector.menuDuration,
  );

  bool _pressed = false;

  bool get _open =>
      _portal.isShowing && _menu.status != AnimationStatus.reverse;

  void _show() {
    _portal.show();
    _menu.forward(from: 0);
  }

  Future<void> _hide() async {
    if (!_portal.isShowing) return;
    await _menu.reverse();
    if (mounted) _portal.hide();
  }

  void _toggle() => _open ? _hide() : _show();

  void _select(KoiInputMode mode) {
    final uid = ref.read(authServiceProvider).user?.uid;
    if (uid == null) return;
    ref.read(inputModeControllerProvider(uid)).select(mode);
    _hide();
  }

  @override
  void dispose() {
    _menu.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(effectiveInputModeProvider);
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: _buildMenuOverlay,
        child: Semantics(
          button: true,
          label: 'Mode: ${mode.label}',
          excludeSemantics: true,
          child: GestureDetector(
            key: const Key('mode-selector-button'),
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            onTap: _toggle,
            // whileTap={{ x: 5, y: 5, boxShadow: none }}
            child: Transform.translate(
              offset: _pressed ? const Offset(5, 5) : Offset.zero,
              child: Container(
                // px-3 py-1 border-[2px] border-black rounded-full
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: KoiColors.neoBlack, width: 2),
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        mode.label,
                        key: const Key('mode-selector-label'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _textSm,
                      ),
                    ),
                    const SizedBox(width: 8), // gap-2
                    const KoiNavIcon(
                      KoiNavGlyph.chevronDown,
                      color: KoiColors.neoBlack,
                      size: 14, // width="14" height="14"
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuOverlay(BuildContext context) {
    return Stack(
      children: [
        // Tap outside closes (mobile stand-in for onMouseLeave).
        Positioned.fill(
          child: GestureDetector(
            key: const Key('mode-selector-barrier'),
            behavior: HitTestBehavior.translucent,
            onTap: _hide,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          // absolute top-full right-0 mt-2
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, 8),
          child: Align(
            alignment: Alignment.topRight,
            child: AnimatedBuilder(
              animation: _menu,
              builder: (context, child) {
                // initial {y:-10, opacity:0} → animate {y:0, opacity:1};
                // exit {y:-8, opacity:0}; transition {duration: 0.2}. The
                // source sets no easing; easeOut here is an approximation
                // of Framer Motion's default, not a verified match.
                final t = Curves.easeOut.transform(_menu.value);
                final fromY = _menu.status == AnimationStatus.reverse
                    ? -8.0
                    : -10.0;
                return Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, fromY * (1 - t)),
                    child: child,
                  ),
                );
              },
              child: Consumer(builder: (context, ref, _) => _buildMenu(ref)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMenu(WidgetRef ref) {
    const modes = KoiInputMode.values;
    final selected = ref.watch(effectiveInputModeProvider);
    final fox = ref.watch(foxTextOnlyProvider);
    return Container(
      key: const Key('mode-selector-menu'),
      // w-64 bg-white border-[3px] border-black rounded-2xl
      // shadow-[5px_5px_0px_0px_rgba(0,0,0,1)] overflow-hidden
      width: ModeSelector.menuWidth,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: KoiColors.neoWhite,
        border: Border.all(color: KoiColors.neoBlack, width: 3),
        borderRadius: BorderRadius.circular(16),
        boxShadow: KoiShadows.hardShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.all(8), // p-2
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < modes.length; i++) ...[
                _ModeItem(
                  mode: modes[i],
                  selected: modes[i] == selected,
                  enabled: !fox || modes[i] == KoiInputMode.text,
                  onTap: () => _select(modes[i]),
                ),
                if (i < modes.length - 1)
                  // h-px bg-gray-300 my-1
                  Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: _gray300,
                  ),
              ],
              if (fox)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Text(
                    ModeSelector.foxNote,
                    key: const Key('mode-fox-note'),
                    // text-xs text-gray-600 (web's hint style)
                    style: KoiText.body(
                      fontSize: 12,
                      height: 16 / 12,
                      color: _gray600,
                      letterSpacing: 0,
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

// font-bold text-sm (0.875rem / line-height 1.25rem). No font-family on the
// nav, so it inherits body: var(--font-body) = DM Sans (globals.css).
final TextStyle _textSm = KoiText.body(
  fontSize: 14,
  height: 20 / 14,
  fontWeight: FontWeight.w700,
  color: KoiColors.neoBlack,
  letterSpacing: 0, // CSS `normal`, not the Material theme's 0.25
);

const Color _gray300 = Color(0xFFD1D5DB); // Tailwind gray-300
const Color _gray600 = Color(0xFF4B5563); // Tailwind gray-600
const Color _slate200 = Color(0xFFE2E8F0); // Tailwind slate-200

class _ModeItem extends StatelessWidget {
  const _ModeItem({
    required this.mode,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final KoiInputMode mode;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Widget item = Container(
      // p-3 rounded-lg
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: selected ? _slate200 : null, // item.id === mode ? bg-slate-200
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(mode.label, style: _textSm),
    );
    if (!enabled) {
      // opacity-50 cursor-not-allowed locked-stripes
      item = Opacity(
        opacity: 0.5,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CustomPaint(
            painter: const _LockedStripesPainter(),
            child: item,
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: GestureDetector(
        key: Key('mode-item-${mode.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: item,
      ),
    );
  }
}

/// globals.css `.locked-stripes`: linear-gradient(135deg, rgba(0,0,0,0.03)
/// 25%, transparent 25%, transparent 50%, rgba(0,0,0,0.03) 50%,
/// rgba(0,0,0,0.03) 75%, transparent 75%, transparent), background-size 12px.
class _LockedStripesPainter extends CustomPainter {
  const _LockedStripesPainter();

  static const double tile = 12;
  static const Color stripe = Color(0x08000000); // rgba(0,0,0,0.03)
  static const Color clear = Color(0x00000000);

  @override
  void paint(Canvas canvas, Size size) {
    // 135deg on a square tile runs corner to corner, top-left → bottom-right.
    const gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [stripe, stripe, clear, clear, stripe, stripe, clear, clear],
      stops: [0, .25, .25, .5, .5, .75, .75, 1],
    );
    for (var y = 0.0; y < size.height; y += tile) {
      for (var x = 0.0; x < size.width; x += tile) {
        final rect = Rect.fromLTWH(x, y, tile, tile);
        canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
      }
    }
  }

  @override
  bool shouldRepaint(_LockedStripesPainter old) => false;
}
