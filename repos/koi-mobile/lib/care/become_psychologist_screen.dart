import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_providers.dart';
import '../account/capability_gate.dart';
import '../account/destinations.dart';
import '../widgets/neo_card.dart';
import 'care_strings.dart';
import 'care_widgets.dart';

/// MOB-5 "Become a Psychologist" (ProfessionalEntry.tsx on
/// origin/feat/koi2-ui-overhaul f9ed940): information only. No form, no
/// website button, no professional workspace and no capability change on
/// mobile; psychologist accounts are created and verified on the website.
class BecomePsychologistScreen extends ConsumerWidget {
  const BecomePsychologistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => CapabilityGate(
    destination: KoiDestination.becomePsychologist,
    builder: (_) {
      final s = ref.watch(careStringsProvider);
      return CarePage(
        key: const Key('become-psychologist'),
        demo: ref.watch(capabilityControllerProvider).isMock,
        title: s.t(CareText.m5BecomeTitle),
        children: [
          NeoCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    s.t(CareText.m5BecomeHeading),
                    style: careBody(s, size: 17, weight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                Text(s.t(CareText.m5BecomeBody), style: careBody(s)),
                const SizedBox(height: 8),
                Text(s.t(CareText.m5BecomeNoChange), style: careMuted(s)),
              ],
            ),
          ),
        ],
      );
    },
  );
}
