import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../experts/expert_screens.dart';
import '../questionnaires/questionnaire_screens.dart';
import '../theme/koi_colors.dart';
import '../theme/koi_radii.dart';
import '../widgets/neo_card.dart';
import 'account_providers.dart';
import 'account_widgets.dart';
import 'capability_gate.dart';
import 'destinations.dart';

/// The Care tab (General / Patient only). Its own navigator keeps the top
/// nav visible, like the Settings tab.
class CareTab extends StatelessWidget {
  const CareTab({super.key, this.navigatorKey});

  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) => Navigator(
    key: navigatorKey,
    onGenerateRoute: (_) => PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      pageBuilder: (context, _, _) => const CareScreen(),
    ),
  );
}

class CareScreen extends ConsumerWidget {
  const CareScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => CapabilityGate(
    destination: KoiDestination.care,
    builder: (context) {
      final caps = ref.watch(effectiveCapabilitiesProvider);
      final demo = ref.watch(capabilityControllerProvider).isMock;
      final relationship = caps.relationship;
      return KoiPage(
        demo: demo,
        title: 'Care',
        children: [
          if (caps.isPatient && relationship != null) ...[
            CareEntry(
              key: const Key('care-psychologist'),
              title: 'My Psychologist',
              subtitle: relationship.psychologistDisplayName,
              onTap: () =>
                  pushKoiPage<void>(context, const MyPsychologistScreen()),
            ),
            if (caps.canUseQuestionnaires)
              CareEntry(
                key: const Key('care-questionnaires'),
                title: 'Questionnaires',
                subtitle: 'Forms your psychologist asked you to fill in',
                onTap: () =>
                    pushKoiPage<void>(context, const QuestionnaireListScreen()),
              ),
            const CareEntry(
              key: Key('care-messages'),
              title: 'Messages',
              subtitle: comingLater,
            ),
            const CareEntry(
              key: Key('care-appointments'),
              title: 'Appointments',
              subtitle: comingLater,
            ),
            const CareEntry(
              key: Key('care-notifications'),
              title: 'Notifications',
              subtitle: comingLater,
            ),
          ],
          if (caps.canDiscoverExperts)
            CareEntry(
              key: const Key('care-experts'),
              title: 'Find an Expert',
              subtitle: 'Browse psychologists listed in KOI',
              onTap: () => pushKoiPage<void>(context, const ExpertListScreen()),
            ),
        ],
      );
    },
  );

  static const String comingLater = 'Coming in a later update';
}

/// One Care row: a Neo card (white when it opens something, grey and
/// labelled when it is not available yet). 48dp+ touch target.
class CareEntry extends StatelessWidget {
  const CareEntry({
    super.key,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: koiMinTouch),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: koiBodyStyle(size: 16.5, weight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: koiMutedStyle()),
              ],
            ),
          ),
          if (enabled) Text('›', style: koiTitleStyle(24), semanticsLabel: ''),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Semantics(
        button: enabled,
        enabled: enabled,
        label: '$title. $subtitle',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: enabled
              ? NeoCard(padding: const EdgeInsets.all(16), child: content)
              : Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: KoiColors.neoGray,
                    border: Border.all(width: 2),
                    borderRadius: KoiRadii.neoAll,
                  ),
                  child: content,
                ),
        ),
      ),
    );
  }
}

/// The patient's relationship: only the name the server returns.
class MyPsychologistScreen extends ConsumerWidget {
  const MyPsychologistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => CapabilityGate(
    destination: KoiDestination.myPsychologist,
    builder: (_) {
      final rel = ref.watch(effectiveCapabilitiesProvider).relationship;
      return KoiPage(
        back: true,
        demo: ref.watch(capabilityControllerProvider).isMock,
        title: 'My Psychologist',
        children: [
          NeoCard(
            padding: const EdgeInsets.all(18),
            child: Text(
              rel?.psychologistDisplayName ?? '',
              style: koiBodyStyle(size: 18, weight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 20),
          const KoiNoticeCard(
            yellow: true,
            message:
                'Messages and appointments with your psychologist are coming '
                'in a later update. This app is not monitored for '
                'emergencies: in a crisis, use the helplines in Settings.',
          ),
        ],
      );
    },
  );
}
