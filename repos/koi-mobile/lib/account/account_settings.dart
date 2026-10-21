import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../platform/platform_config.dart';
import '../settings/widgets/settings_widgets.dart';
import '../shell/shell_tabs.dart';
import '../shell/top_nav.dart' show KoiTab;
import '../theme/koi_colors.dart';
import '../widgets/neo_button.dart';
import '../widgets/neo_card.dart';
import 'account_auth_screen.dart';
import 'account_providers.dart';
import 'account_widgets.dart';
import 'capabilities.dart';
import 'capability_controller.dart';

/// Settings → Account secondary line while the account has no usable Care
/// area (capabilities unavailable, or not set up for Care).
const String accountNoCareText = "Care features aren't available yet";

/// The MOB-1 rows at the top of the Settings "Account" card, in the
/// existing SettingsRow style.
/// - Anonymous: "Create an account" (keeps this uid) and "Sign in".
/// - Registered: the account email, account-feature status (Retry), and
///   "Sign out".
/// - Debug + KOI_MOCKS only: the demo role picker.
class AccountSettingsRows extends ConsumerWidget {
  const AccountSettingsRows({super.key});

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(20),
        child: NeoCard(
          variant: NeoCardVariant.elevated,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Sign out?', style: koiTitleStyle(22)),
              const SizedBox(height: 8),
              Text(
                'Your history stays in your account. You will need your '
                'password to open it again.',
                style: koiBodyStyle(),
              ),
              const SizedBox(height: 20),
              NeoButton(
                key: const Key('sign-out-confirm'),
                fullWidth: true,
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Sign out'),
              ),
              const SizedBox(height: 10),
              NeoButton(
                variant: NeoButtonVariant.ghost,
                fullWidth: true,
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true) await ref.read(accountControllerProvider).signOut();
  }

  Future<void> _pickRole(BuildContext context, WidgetRef ref) async {
    final source = ref.read(capabilitiesSourceProvider);
    if (source is! MockCapabilitiesSource) return;
    final role = await showDialog<KoiRole>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Demo role (debug)', style: koiTitleStyle(20)),
        backgroundColor: KoiColors.neoWhite,
        children: [
          for (final r in KoiRole.values)
            SimpleDialogOption(
              key: Key('demo-role-${r.name}'),
              onPressed: () => Navigator.of(context).pop(r),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(r.name, style: koiBodyStyle()),
              ),
            ),
        ],
      ),
    );
    if (role == null) return;
    source.role.value = role;
    await ref.read(capabilityControllerProvider).refresh();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authServiceProvider);
    final user = auth.user;
    if (user == null) return const SizedBox.shrink();
    final caps = ref.watch(capabilityControllerProvider);
    final rows = <Widget>[];
    if (user.isAnonymous) {
      rows.addAll([
        SettingsRow(
          key: const Key('row-create-account'),
          icon: '🔑',
          label: 'Create an account',
          desc: 'Keep this KOI history in an account',
          onTap: () => pushKoiPage<void>(
            context,
            const AccountAuthScreen(mode: AccountFormMode.upgrade),
          ),
        ),
        const SettingsDivider(),
        SettingsRow(
          key: const Key('row-sign-in'),
          icon: '↪',
          label: 'Sign in',
          desc: 'Use an account you already have',
          onTap: () => pushKoiPage<void>(
            context,
            const AccountAuthScreen(mode: AccountFormMode.signIn),
          ),
        ),
      ]);
    } else {
      // LIVE-READY: who is signed in, and a calm note while Care can't be
      // used. Tapping opens the Care tab, which shows the account's Care
      // status (with Retry) or the Care home.
      final noCare =
          caps.status == CapabilityStatus.unavailable ||
          caps.effective.careNotSetUp;
      final tabs = ShellTabs.maybeOf(context);
      final email = user.email;
      rows.addAll([
        SettingsRow(
          key: const Key('row-account'),
          icon: '✉',
          label: email == null || email.isEmpty
              ? 'Signed in'
              : 'Signed in as $email',
          desc: noCare ? accountNoCareText : '',
          onTap: tabs == null ? null : () => tabs.select(KoiTab.care),
        ),
        const SettingsDivider(),
        SettingsRow(
          key: const Key('row-sign-out'),
          icon: '⎋',
          label: 'Sign out',
          desc: 'Sign out of this account on this device',
          onTap: () => _confirmSignOut(context, ref),
        ),
      ]);
    }
    if (koiMockRolePicker && !user.isAnonymous) {
      rows.addAll([
        const SettingsDivider(),
        SettingsRow(
          key: const Key('row-demo-role'),
          icon: '🧪',
          label: 'Demo role (debug)',
          desc: caps.effective.role.name,
          onTap: () => _pickRole(context, ref),
        ),
      ]);
    }
    rows.add(const SettingsDivider());
    return Column(children: rows);
  }
}
