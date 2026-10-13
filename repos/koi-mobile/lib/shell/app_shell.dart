import 'package:flutter/material.dart';

import '../screens/placeholders.dart';
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

  void _select(KoiTab tab) => setState(() => _tab = tab);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoiColors.background,
      body: Column(
        children: [
          KoiTopNav(
            current: _tab,
            onSelect: _select,
            onLogoTap: () => _select(KoiTab.chat),
          ),
          Expanded(
            child: switch (_tab) {
              KoiTab.chat => const ChatPlaceholder(),
              KoiTab.progress => const ProgressPlaceholder(),
              KoiTab.settings => const SettingsPlaceholder(),
            },
          ),
        ],
      ),
    );
  }
}
