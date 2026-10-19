import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../platform/platform_config.dart';
import '../widgets/koi_loader.dart';
import '../widgets/neo_button.dart';
import '../widgets/neo_card.dart';
import '../widgets/neo_input.dart';
import 'account_auth_screen.dart';
import 'account_migration.dart';
import 'account_providers.dart';
import 'account_widgets.dart';
import 'capability_controller.dart';

/// Default-deny while a registered user's capabilities are confirmed: no
/// tab, no cached role, just the loader.
class CapabilityCheckScreen extends StatelessWidget {
  const CapabilityCheckScreen({super.key});

  static const String label = 'Checking your account…';

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: KoiLoadingPage(label: label));
}

/// New device or cleared cache: the account password opens the history.
class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(accountControllerProvider).unlockWith(_password.text);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = accountErrorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Scaffold(body: KoiLoadingPage(label: 'Unlocking…'));
    }
    return KoiPage(
      title: 'Unlock your KOI history',
      children: [
        Text(
          'Enter your account password to open your encrypted history on '
          'this device.',
          style: koiBodyStyle(),
        ),
        const SizedBox(height: 16),
        NeoInput(
          key: const Key('unlock-password'),
          label: 'Password',
          controller: _password,
          obscureText: true,
        ),
        const SizedBox(height: 16),
        Text(passwordWarning, style: koiMutedStyle()),
        if (_error != null) ...[
          const SizedBox(height: 16),
          KoiErrorText(_error!),
        ],
        const SizedBox(height: 24),
        NeoButton(
          key: const Key('unlock-submit'),
          fullWidth: true,
          onPressed: _unlock,
          child: const Text('Unlock'),
        ),
        const SizedBox(height: 14),
        NeoButton(
          key: const Key('unlock-sign-out'),
          variant: NeoButtonVariant.ghost,
          fullWidth: true,
          onPressed: () => ref.read(accountControllerProvider).signOut(),
          child: const Text('Sign out'),
        ),
      ],
    );
  }
}

/// Linking finished; the history is being re-encrypted. Resumes after a
/// restart; an error offers Retry and keeps everything as it was.
class MigrationScreen extends ConsumerWidget {
  const MigrationScreen({super.key});

  static const String label = 'Securing your history…';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountControllerProvider);
    if (account.migrating || account.migrationError == null) {
      return const Scaffold(body: KoiLoadingPage(label: label));
    }
    return KoiPage(
      title: 'Almost there',
      children: [
        KoiNoticeCard(
          message:
              'Your history could not be re-encrypted yet. Nothing was lost: '
              'it stays as it was until this finishes.',
          action: account.retryPending,
          actionLabel: 'Try again',
        ),
      ],
    );
  }
}

/// "Bring this device's KOI history into this account?" Accepting needs the
/// account password again (re-authentication). "Leave it" keeps the
/// history hidden on this device.
class ClaimScreen extends ConsumerStatefulWidget {
  const ClaimScreen({super.key});

  @override
  ConsumerState<ClaimScreen> createState() => _ClaimScreenState();
}

class _ClaimScreenState extends ConsumerState<ClaimScreen> {
  final _password = TextEditingController();
  bool _asking = false;
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final report = await ref
          .read(accountControllerProvider)
          .acceptClaim(_password.text);
      if (mounted && report.state == MigrationState.awaitingAck) {
        setState(
          () => _notice =
              'Copied. The originals stay on this device until the server '
              'confirms it has the copies.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = accountErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Scaffold(
        body: KoiLoadingPage(label: 'Bringing your history across…'),
      );
    }
    return KoiPage(
      title: 'Bring this device\'s KOI history into this account?',
      children: [
        Text(
          'Before signing in, you used KOI on this device without an '
          'account. You can copy those chats and check-ins into this '
          'account, or leave them where they are.',
          style: koiBodyStyle(),
        ),
        if (_notice != null) ...[
          const SizedBox(height: 16),
          KoiNoticeCard(message: _notice!),
        ],
        const SizedBox(height: 20),
        if (_asking) ...[
          NeoInput(
            key: const Key('claim-password'),
            label: 'Confirm this account\'s password',
            controller: _password,
            obscureText: true,
          ),
          const SizedBox(height: 16),
        ],
        if (_error != null) ...[
          KoiErrorText(_error!),
          const SizedBox(height: 16),
        ],
        NeoButton(
          key: const Key('claim-accept'),
          fullWidth: true,
          onPressed: _asking ? _accept : () => setState(() => _asking = true),
          child: const Text('Bring it across'),
        ),
        const SizedBox(height: 14),
        NeoButton(
          key: const Key('claim-leave'),
          variant: NeoButtonVariant.ghost,
          fullWidth: true,
          onPressed: () => ref.read(accountControllerProvider).leaveClaim(),
          child: const Text('Leave it'),
        ),
      ],
    );
  }
}

/// Psychologists manage patients in the web portal. No KOI companion and
/// never a patient screen here.
class PsychologistLandingScreen extends ConsumerWidget {
  const PsychologistLandingScreen({super.key, this.portal, this.openUrl});

  /// Defaults to KOI_PRO_PORTAL_URL; null hides the link.
  final Uri? portal;
  final Future<bool> Function(Uri)? openUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = portal ?? proPortalUri();
    final demo = ref.watch(capabilityControllerProvider).isMock;
    return KoiPage(
      demo: demo,
      title: 'Your KOI professional account',
      children: [
        Text(
          'Patient management happens in the KOI professional web portal. '
          'This app is for KOI members.',
          style: koiBodyStyle(),
        ),
        const SizedBox(height: 24),
        if (url != null) ...[
          NeoButton(
            key: const Key('pro-portal'),
            fullWidth: true,
            onPressed: () =>
                (openUrl ??
                (u) => launchUrl(u, mode: LaunchMode.externalApplication))(url),
            child: const Text('Open the professional portal'),
          ),
          const SizedBox(height: 14),
        ],
        NeoButton(
          key: const Key('pro-sign-out'),
          variant: NeoButtonVariant.ghost,
          fullWidth: true,
          onPressed: () => ref.read(accountControllerProvider).signOut(),
          child: const Text('Sign out'),
        ),
      ],
    );
  }
}

/// The relationship ended: nothing restricted is shown; the patient caches
/// are already gone. KOI itself stays available.
class AccessEndedScreen extends ConsumerWidget {
  const AccessEndedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => KoiPage(
    title: 'Access ended',
    children: [
      NeoCard(
        padding: const EdgeInsets.all(18),
        child: Text(
          'Your access to your psychologist\'s space has ended. Your '
          'questionnaires and related details are no longer available in '
          'this app. KOI is still here for you.',
          style: koiBodyStyle(),
        ),
      ),
      const SizedBox(height: 24),
      NeoButton(
        key: const Key('access-ended-continue'),
        fullWidth: true,
        onPressed: () =>
            ref.read(capabilityControllerProvider).acknowledgeAccessEnded(),
        child: const Text('Continue to KOI'),
      ),
    ],
  );
}

/// Settings line for a registered account whose capabilities could not be
/// confirmed: KOI works, account features stay closed.
String capabilityStatusText(CapabilityStatus s) => switch (s) {
  CapabilityStatus.unavailable =>
    'Account features are not available right now.',
  CapabilityStatus.loading => CapabilityCheckScreen.label,
  _ => '',
};
