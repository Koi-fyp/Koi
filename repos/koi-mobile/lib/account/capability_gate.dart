import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/koi_loader.dart';
import 'account_gate_screens.dart';
import 'account_providers.dart';
import 'account_widgets.dart';
import 'destinations.dart';

/// Wraps every protected screen: it is built only while the CURRENT
/// account's confirmed capabilities allow [destination]. A revoked
/// relationship, a role change or a 403 refresh replaces it at once.
class CapabilityGate extends ConsumerWidget {
  const CapabilityGate({
    super.key,
    required this.destination,
    required this.builder,
  });

  final KoiDestination destination;
  final WidgetBuilder builder;

  static const String deniedText = 'This is not available for your account.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(capabilityControllerProvider);
    final decision = decideDestination(
      destination,
      status: controller.status,
      caps: controller.effective,
    );
    return switch (decision) {
      LinkDecision.allow => builder(context),
      LinkDecision.wait => const Scaffold(
        body: KoiLoadingPage(label: CapabilityCheckScreen.label),
      ),
      LinkDecision.deny || LinkDecision.signIn => const KoiPage(
        key: Key('capability-denied'),
        back: true,
        children: [KoiNoticeCard(message: deniedText)],
      ),
    };
  }
}
