import 'package:flutter/material.dart';

import '../chat/chat_screen.dart';
import '../environment/environment_palette.dart';
import '../environment/environment_providers.dart';
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
class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialTab = KoiTab.chat});

  final KoiTab initialTab;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late KoiTab _tab = widget.initialTab;

  /// The Settings tab's nested navigator (Privacy / Export / Import).
  final GlobalKey<NavigatorState> _settingsNav = GlobalKey<NavigatorState>();

  void _select(KoiTab tab) => setState(() => _tab = tab);

  /// Android back (decision 2026-10-14): a Settings sub-page → Settings;
  /// Progress or Settings → Chat; Chat → leave the app (canPop). Popups are
  /// routes above this one, so back closes them before reaching here.
  void _onBack(bool didPop, Object? _) {
    if (didPop) return;
    final nested = _settingsNav.currentState;
    if (_tab == KoiTab.settings && nested != null && nested.canPop()) {
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
            ),
          ),
          Expanded(
            child: switch (_tab) {
              KoiTab.chat => const ChatScreen(),
              KoiTab.progress => ProgressScreen(
                onOpenChat: () => _select(KoiTab.chat),
              ),
              KoiTab.settings => SettingsTab(navigatorKey: _settingsNav),
            },
          ),
        ],
      ),
    );
  }
}
