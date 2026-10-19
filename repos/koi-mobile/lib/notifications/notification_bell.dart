import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../care/care_providers.dart';
import '../care/care_strings.dart';
import '../shell/nav_icons.dart';
import '../theme/koi_colors.dart';
import '../theme/koi_text.dart';

/// The top-bar bell (Care users only), in the nav's own style: a gray-600
/// stroke icon like the inactive tabs, sitting in the brand pill after the
/// Mode selector. Unread count in a small neoBlue badge (white on #2D63EB
/// = 5.0:1). Below [compactWidth] of free pill space the badge collapses
/// to a dot, so it never overflows at 320dp.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key, required this.onTap});

  final VoidCallback onTap;

  /// Bell box: 48 wide (tap target) × 32 tall (the pill's row height, the
  /// same as the logo and the Mode selector).
  static const double width = 48;
  static const double height = 32;

  static const Color _gray600 = Color(0xFF4B5563);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(careStringsProvider);
    final unread = ref.watch(careSessionProvider.select((c) => c.unreadCount));
    final compact = MediaQuery.sizeOf(context).width < 340;
    return Semantics(
      button: true,
      label: s.notificationsBell(unread),
      excludeSemantics: true,
      child: GestureDetector(
        key: const Key('nav-bell'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              const KoiNavIcon(KoiNavGlyph.bell, color: _gray600, size: 20),
              if (unread > 0)
                PositionedDirectional(
                  top: 0,
                  end: compact ? 12 : 4,
                  child: compact
                      ? Container(
                          key: const Key('nav-bell-dot'),
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: KoiColors.neoBlue,
                            shape: BoxShape.circle,
                            border: Border.all(width: 1.5),
                          ),
                        )
                      : Container(
                          key: const Key('nav-bell-badge'),
                          constraints: const BoxConstraints(minWidth: 18),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: KoiColors.neoBlue,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(width: 1.5),
                          ),
                          child: Text(
                            unread > 9 ? '9+' : '$unread',
                            textAlign: TextAlign.center,
                            style: KoiText.body(
                              fontSize: 11,
                              height: 14 / 11,
                              fontWeight: FontWeight.w700,
                              color: KoiColors.neoWhite,
                              letterSpacing: 0,
                            ),
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

/// The unread-messages badge on the Care tab: a small neoBlue dot drawn
/// over the tab without changing its size (existing nav items unchanged).
class CareTabBadge extends ConsumerWidget {
  const CareTabBadge({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(
      careSessionProvider.select((c) => c.unreadMessageNotifications.length),
    );
    if (unread == 0) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: 2,
          right: 2,
          child: Container(
            key: const Key('nav-care-unread'),
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: KoiColors.neoBlue,
              shape: BoxShape.circle,
              border: Border.all(width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
