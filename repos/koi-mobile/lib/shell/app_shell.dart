import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_providers.dart';
import '../account/account_widgets.dart' show pushKoiPage;
import '../account/capability_controller.dart';
import '../account/care_screen.dart';
import '../app/providers.dart';
import '../chat/chat_screen.dart';
import '../environment/environment_palette.dart';
import '../environment/environment_providers.dart';
import '../notifications/notification_bell.dart';
import '../notifications/notification_screens.dart';
import '../progress/progress_screen.dart';
import '../safety/safety_host.dart';
import '../settings/settings_screen.dart';
import '../theme/koi_colors.dart';
import 'top_nav.dart';

/// Signed-in shell, mirroring
/// repos/koi-backend/nextjs_app/src/app/(authenticated)/layout.tsx:
/// the top nav above the page (`flex-col`, `main { flex: 1 }`). Web pads the
/// page by 66px because its nav is `position: fixed`; here the nav is simply
/// laid out above the page, so no padding is needed.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, this.initialTab = KoiTab.chat});

  final KoiTab initialTab;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  late KoiTab _tab = widget.initialTab;

  /// The Settings tab's nested navigator (Privacy / Export / Import).
  final GlobalKey<NavigatorState> _settingsNav = GlobalKey<NavigatorState>();

  /// The Care tab's nested navigator (MOB-1).
  final GlobalKey<NavigatorState> _careNav = GlobalKey<NavigatorState>();

  /// The Care area was confirmed before the current capability re-check.
  bool _hadCare = false;

  /// The Care tab was shown (any page) before the current re-check.
  bool _hadCareTab = false;

  void _select(KoiTab tab) => setState(() => _tab = tab);

  /// MOB-2 bell: the inbox opens inside the Care tab, so the top nav stays.
  void _openInbox() {
    _select(KoiTab.care);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = _careNav.currentState;
      if (nav == null || !mounted) return;
      nav.popUntil((r) => r.isFirst);
      pushKoiPage<void>(nav.context, const NotificationInboxScreen());
    });
  }

  /// Android back (decision 2026-10-14): a Settings sub-page → Settings;
  /// Progress or Settings → Chat; Chat → leave the app (canPop). Popups are
  /// routes above this one, so back closes them before reaching here.
  void _onBack(bool didPop, Object? _) {
    if (didPop) return;
    final nested = switch (_tab) {
      KoiTab.settings => _settingsNav.currentState,
      KoiTab.care => _careNav.currentState,
      _ => null,
    };
    if (nested != null && nested.canPop()) {
      nested.pop();
      return;
    }
    if (_tab != KoiTab.chat) _select(KoiTab.chat);
  }

  @override
  Widget build(BuildContext context) {
    // Web switches tabs with routes, so browser back walks the history.
    // Mobile swaps the tab in place, so back is handled here instead.
    return PopScope<Object?>(
      canPop: _tab == KoiTab.chat,
      onPopInvokedWithResult: _onBack,
      // Crisis (Flow 4) and breathing screens open above any page.
      child: SafetyHost(child: _scaffold()),
    );
  }

  Widget _scaffold() {
    // MOB-1: the Care tab exists only while the backend confirms a Care
    // area for THIS account (default-deny). Losing it closes the tab.
    // MOB-2: while a re-check runs (e.g. after a 403) the tab stays, but
    // its gates show only the loader (still default-deny: nothing
    // protected is built). It goes only when the server says so.
    final controller = ref.watch(capabilityControllerProvider);
    final confirmed = controller.effective.hasCareArea;
    final checking = controller.status == CapabilityStatus.loading;
    if (!checking) _hadCare = confirmed;
    final hasCare = confirmed || (checking && _hadCare);
    // AUTH-ENTRY: anonymous users get the tab as an information page (no
    // Care data, no Care call), and registered users whose account
    // features cannot be confirmed get the calm "not available yet". The
    // bell and badge stay for a confirmed Care area only.
    final anonymous = ref.watch(
      authServiceProvider.select((a) => a.user?.isAnonymous ?? false),
    );
    // MOB-4: a registered account the server has not set up for Care
    // (`unregistered`, or no General access) gets the "not set up yet" page.
    // A Retry from that page or the "not available" one keeps the tab
    // while it checks.
    final careTabNow =
        hasCare ||
        anonymous ||
        controller.status == CapabilityStatus.unavailable ||
        controller.effective.careNotSetUp;
    if (!checking) _hadCareTab = careTabNow;
    final careTab = careTabNow || (checking && _hadCareTab);
    if (!careTab && _tab == KoiTab.care) _tab = KoiTab.chat;
    return Scaffold(
      backgroundColor: KoiColors.background,
      body: Column(
        children: [
          // The Chat tab tints the nav strip with its background.
          EnvironmentColorBuilder(
            strength: _tab == KoiTab.chat ? EnvironmentPalette.chatStrength : 0,
            builder: (context, color, _) => KoiTopNav(
              current: _tab,
              onSelect: _select,
              onLogoTap: () => _select(KoiTab.chat),
              background: color,
              trailing: hasCare ? NotificationBell(onTap: _openInbox) : null,
              wrapTab: hasCare
                  ? (tab, child) =>
                        tab == KoiTab.care ? CareTabBadge(child: child) : child
                  : null,
              tabs: careTab
                  ? const [
                      KoiTab.chat,
                      KoiTab.progress,
                      KoiTab.care,
                      KoiTab.settings,
                    ]
                  : KoiTopNav.defaultTabs,
            ),
          ),
          Expanded(
            child: switch (_tab) {
              KoiTab.chat => const ChatScreen(),
              KoiTab.progress => ProgressScreen(
                onOpenChat: () => _select(KoiTab.chat),
              ),
              KoiTab.settings => SettingsTab(navigatorKey: _settingsNav),
              KoiTab.care => CareTab(navigatorKey: _careNav),
            },
          ),
        ],
      ),
    );
  }
}
