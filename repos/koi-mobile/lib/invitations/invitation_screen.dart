import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_providers.dart';
import '../account/account_widgets.dart';
import '../account/capability_gate.dart';
import '../account/destinations.dart';
import '../care/care_api_support.dart';
import '../care/care_providers.dart';
import '../care/care_strings.dart';
import '../care/care_widgets.dart';
import '../widgets/neo_input.dart';
import 'invitation_api.dart';

/// The Care text for a failed redeem (MOB-4 answer 4: one message for
/// expired / cancelled / already used, the server cannot tell them apart).
String invitationFailureText(CareStrings s, InvitationFailure f) =>
    s.t(switch (f) {
      InvitationFailure.format => CareText.m4InviteFormat,
      InvitationFailure.notFound => CareText.m4InviteNotFound,
      InvitationFailure.used => CareText.m4InviteUsed,
      InvitationFailure.denied => CareText.m4InviteDenied,
      InvitationFailure.rateLimited => CareText.rateLimited,
      InvitationFailure.offline => CareText.offline,
      InvitationFailure.notAvailable => CareText.notAvailableYet,
      InvitationFailure.reauth ||
      InvitationFailure.other => CareText.genericError,
    });

/// Care → "I have an invitation code": paste the code (or the web link),
/// agree, accept. On success the capabilities are re-checked, so the
/// Patient area appears on the Care home without signing out.
class InvitationScreen extends StatelessWidget {
  const InvitationScreen({super.key});

  @override
  Widget build(BuildContext context) => CapabilityGate(
    destination: KoiDestination.invitation,
    builder: (_) => const _Invitation(),
  );
}

class _Invitation extends ConsumerStatefulWidget {
  const _Invitation();

  @override
  ConsumerState<_Invitation> createState() => _InvitationState();
}

class _InvitationState extends ConsumerState<_Invitation> {
  // The ONLY place the token lives: never saved, logged or copied.
  final _code = TextEditingController();
  bool _consent = false;
  bool _showConsentError = false;
  bool _busy = false;
  String? _error;

  /// One "Accept invitation" action = one key; a retry of the same code
  /// reuses it, a different code gets a new one.
  String _key = newIdempotencyKey();
  String? _keyFor;

  @override
  void dispose() {
    _code.clear();
    _code.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final s = ref.read(careStringsProvider);
    final token = parseInvitationToken(_code.text);
    if (token == null) {
      setState(() => _error = s.t(CareText.m4InviteFormat));
      return;
    }
    if (!_consent) {
      setState(() => _showConsentError = true);
      return;
    }
    if (_keyFor != token) {
      _key = newIdempotencyKey();
      _keyFor = token;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = ref.read(invitationApiProvider);
    final key = _key;
    try {
      await runCareMutation(
        context,
        ref,
        () => api.redeem(token, idempotencyKey: key),
      );
      _code.clear();
      _keyFor = null;
      // authorization_revision changed: the Patient area comes from the
      // server's answer, never from the ack alone.
      await ref.read(capabilityControllerProvider).refresh(silent: true);
      if (!mounted) return;
      ref.read(careSessionProvider).showNotice(CareText.m4InviteAccepted);
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = invitationFailureText(s, invitationFailureOf(e));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(careStringsProvider);
    return Directionality(
      textDirection: s.direction,
      child: KoiPage(
        key: const Key('invitation-page'),
        back: true,
        backLabel: s.t(CareText.back),
        demo: ref.watch(invitationApiProvider).isMock,
        title: s.t(CareText.m4InviteTitle),
        children: [
          Text(s.t(CareText.m4InviteIntro), style: careBody(s)),
          const SizedBox(height: 18),
          NeoInput(
            key: const Key('invitation-code'),
            label: s.t(CareText.m4InviteLabel),
            placeholder: s.t(CareText.m4InviteHint),
            controller: _code,
            enabled: !_busy,
            // No suggestions / keyboard learning of the secret code.
            keyboardType: TextInputType.visiblePassword,
            textDirection: TextDirection.ltr,
            maxLength: 2048,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 18),
          CareCheckRow(
            key: const Key('invitation-consent'),
            strings: s,
            label: s.t(CareText.m4InviteConsent),
            checked: _consent,
            onChanged: _busy
                ? () {}
                : () => setState(() {
                    _consent = !_consent;
                    _showConsentError = false;
                  }),
          ),
          if (_showConsentError) ...[
            const SizedBox(height: 8),
            KoiErrorText(s.t(CareText.consentNeeded)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            KoiErrorText(_error!, key: const Key('invitation-error')),
          ],
          const SizedBox(height: 20),
          CareActionButton(
            key: const Key('invitation-redeem'),
            label: s.t(CareText.m4InviteRedeem),
            busyLabel: s.t(CareText.m4InviteRedeeming),
            busy: _busy,
            onPressed: _redeem,
          ),
        ],
      ),
    );
  }
}
