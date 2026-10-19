import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../care/care_providers.dart';
import '../care/care_strings.dart';
import '../widgets/koi_loader.dart';
import 'account_gate_screens.dart';
import 'account_providers.dart';
import 'account_widgets.dart';
import 'destinations.dart';

/// Wraps every protected screen: it is built only while the CURRENT
/// account's confirmed capabilities allow [destination]. A revoked
/// relationship, a role change or a 403 refresh replaces it at once.
///
/// MOB-2: when a screen that WAS allowed loses access while open (and it
/// was pushed, e.g. a Patient screen in the Care tab), it is popped back to
/// the first route after the frame, with a calm notice on the Care home.
/// Nothing restricted is built in between.
class CapabilityGate extends ConsumerStatefulWidget {
  const CapabilityGate({
    super.key,
    required this.destination,
    required this.builder,
  });

  final KoiDestination destination;
  final WidgetBuilder builder;

  static const String deniedText = 'This is not available for your account.';

  @override
  ConsumerState<CapabilityGate> createState() => _CapabilityGateState();
}

class _CapabilityGateState extends ConsumerState<CapabilityGate> {
  bool _wasAllowed = false;
  bool _popping = false;

  void _revoked() {
    if (_popping) return;
    final nav = Navigator.maybeOf(context);
    if (nav == null || !nav.canPop()) return;
    _popping = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(careSessionProvider).showNotice(CareText.noLongerAvailable);
      Navigator.of(context).popUntil((r) => r.isFirst);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(capabilityControllerProvider);
    final decision = decideDestination(
      widget.destination,
      status: controller.status,
      caps: controller.effective,
    );
    if (decision == LinkDecision.allow) _wasAllowed = true;
    if (_wasAllowed &&
        (decision == LinkDecision.deny || decision == LinkDecision.signIn)) {
      _revoked();
    }
    return switch (decision) {
      LinkDecision.allow => widget.builder(context),
      LinkDecision.wait => const Scaffold(
        body: KoiLoadingPage(label: CapabilityCheckScreen.label),
      ),
      LinkDecision.deny || LinkDecision.signIn => const KoiPage(
        key: Key('capability-denied'),
        back: true,
        children: [KoiNoticeCard(message: CapabilityGate.deniedText)],
      ),
    };
  }
}
