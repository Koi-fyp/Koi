import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../care/care_strings.dart';
import '../care/care_widgets.dart';
import '../core/key_value_store.dart';
import '../theme/koi_colors.dart';
import '../widgets/neo_button.dart';
import '../widgets/neo_card.dart';
import 'account_auth_screen.dart';
import 'account_providers.dart';
import 'account_widgets.dart';

// AUTH-ENTRY: the places that lead to the MOB-1 account form. None of them
// has auth logic of its own; they only open AccountAuthScreen.

/// Create account: links an anonymous user (same uid, history kept and
/// re-encrypted); signed out → a new account.
void openCreateAccount(BuildContext context, WidgetRef ref) {
  final anonymous = ref.read(authServiceProvider).isAnonymous;
  pushKoiPage<void>(
    context,
    AccountAuthScreen(
      mode: anonymous ? AccountFormMode.upgrade : AccountFormMode.create,
    ),
  );
}

/// Sign in to an existing account (the MOB-1 claim / switch flow).
void openSignIn(BuildContext context) => pushKoiPage<void>(
  context,
  const AccountAuthScreen(mode: AccountFormMode.signIn),
);

/// "Create account" (primary) and "Sign in" (secondary), full width.
class AccountChoiceButtons extends ConsumerWidget {
  const AccountChoiceButtons({
    super.key,
    this.keyPrefix = 'auth',
    this.enabled = true,
  });

  /// Keys: `<prefix>-create-account`, `<prefix>-sign-in`.
  final String keyPrefix;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(careStringsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: koiMinTouch),
          child: NeoButton(
            key: Key('$keyPrefix-create-account'),
            fullWidth: true,
            onPressed: enabled ? () => openCreateAccount(context, ref) : null,
            child: CareButtonLabel(s.t(CareText.auCreateButton)),
          ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: koiMinTouch),
          child: NeoButton(
            key: Key('$keyPrefix-sign-in'),
            variant: NeoButtonVariant.secondary,
            fullWidth: true,
            onPressed: enabled ? () => openSignIn(context) : null,
            child: CareButtonLabel(s.t(CareText.auSignInButton)),
          ),
        ),
      ],
    );
  }
}

/// A plain underlined text link with a 48dp target.
class KoiTextLink extends StatelessWidget {
  const KoiTextLink({
    super.key,
    required this.label,
    required this.onTap,
    this.strings,
  });

  final String label;
  final VoidCallback onTap;
  final CareStrings? strings;

  @override
  Widget build(BuildContext context) {
    final s = strings ?? CareStrings.en;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: koiMinTouch,
            minWidth: koiMinTouch,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Align(
              widthFactor: 1,
              heightFactor: 1,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                label,
                style: careBody(
                  s,
                  size: 14.5,
                  weight: FontWeight.w700,
                ).copyWith(decoration: TextDecoration.underline),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "I'm a psychologist" → information only. Roles never come from the app:
/// only from the server's capabilities.
class PsychologistLink extends ConsumerWidget {
  const PsychologistLink({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(careStringsProvider);
    return KoiTextLink(
      key: const Key('auth-psychologist'),
      label: s.t(CareText.auPsychLink),
      strings: s,
      onTap: () => showPsychologistInfo(context, s),
    );
  }
}

Future<void> showPsychologistInfo(BuildContext context, CareStrings s) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Directionality(
        textDirection: s.direction,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: NeoCard(
              key: const Key('psychologist-info'),
              variant: NeoCardVariant.elevated,
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      s.t(CareText.auPsychTitle),
                      style: koiTitleStyle(22)
                          .copyWith(height: s.isUrdu ? 1.6 : null),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(s.t(CareText.auPsychBody), style: careBody(s)),
                  const SizedBox(height: 20),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: koiMinTouch),
                    child: NeoButton(
                      key: const Key('psychologist-info-ok'),
                      fullWidth: true,
                      onPressed: () => Navigator.of(context).pop(),
                      child: CareButtonLabel(s.t(CareText.ok)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

/// The Care tab of an anonymous user: information and the two buttons
/// only. It reads no Care provider and calls no API (anonymous access to
/// Care stays prohibited).
class AnonymousCareScreen extends ConsumerWidget {
  const AnonymousCareScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(careStringsProvider);
    return CarePage(
      key: const Key('care-anonymous'),
      back: false,
      title: s.t(CareText.auCareTitle),
      children: [
        Text(s.t(CareText.auCareWhy), style: careBody(s, size: 16)),
        const SizedBox(height: 12),
        Text(s.t(CareText.auWhy), style: careBody(s, size: 16)),
        const SizedBox(height: 12),
        Text(s.t(CareText.auCareKeep), style: careMuted(s, 14)),
        const SizedBox(height: 24),
        const AccountChoiceButtons(keyPrefix: 'care'),
        const SizedBox(height: 16),
        Text(s.t(CareText.auCareChat), style: careMuted(s, 14)),
      ],
    );
  }
}

/// The Care tab of a registered user while the platform backend cannot
/// confirm the account features: a calm notice and Retry. KOI chat is not
/// affected.
class CareUnavailableScreen extends ConsumerWidget {
  const CareUnavailableScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(careStringsProvider);
    return CarePage(
      key: const Key('care-unavailable'),
      back: false,
      title: s.t(CareText.care),
      children: [
        KoiNoticeCard(
          message: s.t(CareText.notAvailableYet),
          actionLabel: s.t(CareText.retry),
          action: () => ref.read(capabilityControllerProvider).refresh(),
        ),
      ],
    );
  }
}

/// MOB-4: the Care tab of a signed-in (non-anonymous) account the server
/// has not set up for Care: `account_state` is not `registered` (a new
/// Email/Password account is `unregistered`), or every capability is off.
/// A calm notice and Retry; no sign-in buttons (the user IS signed in), no
/// Care call, no invitation entry (the server would refuse it).
class CareNotSetUpScreen extends ConsumerWidget {
  const CareNotSetUpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(careStringsProvider);
    return CarePage(
      key: const Key('care-not-set-up'),
      back: false,
      title: s.t(CareText.care),
      children: [
        KoiNoticeCard(
          message: s.t(CareText.m4NotSetUp),
          actionLabel: s.t(CareText.retry),
          action: () => ref.read(capabilityControllerProvider).refresh(),
        ),
        const SizedBox(height: 16),
        Text(s.t(CareText.m4NotSetUpChat), style: careMuted(s, 14)),
      ],
    );
  }
}

/// Settings → Account, anonymous users: a small card with the two buttons,
/// until dismissed (per uid, on this device).
class AccountEntryCard extends ConsumerStatefulWidget {
  const AccountEntryCard({super.key});

  static String dismissedKey(String uid) => 'koi_auth_card_dismissed_$uid';

  @override
  ConsumerState<AccountEntryCard> createState() => _AccountEntryCardState();
}

class _AccountEntryCardState extends ConsumerState<AccountEntryCard> {
  bool _dismissed = false;

  KeyValueStore get _prefs => ref.read(localPrefsProvider);

  Future<void> _dismiss(String uid) async {
    setState(() => _dismissed = true);
    try {
      await _prefs.put(AccountEntryCard.dismissedKey(uid), 'true');
    } catch (_) {
      // Hidden for now; it may come back next time.
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authServiceProvider).user;
    if (user == null || !user.isAnonymous || _dismissed) {
      return const SizedBox.shrink();
    }
    bool stored;
    try {
      stored = _prefs.get(AccountEntryCard.dismissedKey(user.uid)) == 'true';
    } catch (_) {
      stored = false;
    }
    if (stored) return const SizedBox.shrink();
    final s = ref.watch(careStringsProvider);
    return Directionality(
      textDirection: s.direction,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: NeoCard(
          key: const Key('account-entry-card'),
          variant: NeoCardVariant.yellow,
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        s.t(CareText.auCareTitle),
                        style: careBody(s, size: 16, weight: FontWeight.w700),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: koiMinTouch,
                    height: koiMinTouch,
                    child: IconButton(
                      key: const Key('account-entry-dismiss'),
                      tooltip: s.t(CareText.auDismiss),
                      icon: const Icon(Icons.close, color: KoiColors.neoBlack),
                      onPressed: () => _dismiss(user.uid),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8, bottom: 12),
                child: Text(s.t(CareText.auWhy), style: careBody(s, size: 14)),
              ),
              const Padding(
                padding: EdgeInsetsDirectional.only(end: 8),
                child: AccountChoiceButtons(keyPrefix: 'settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
