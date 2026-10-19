import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../applications/application_screens.dart';
import '../appointments/appointment_screens.dart';
import '../care/care_providers.dart';
import '../care/care_strings.dart';
import '../care/care_widgets.dart';
import '../care/simulate_menu.dart';
import '../care_messages/message_screens.dart';
import '../experts/expert_screens.dart';
import '../notifications/notification_screens.dart';
import '../questionnaires/questionnaire_screens.dart';
import '../theme/koi_colors.dart';
import '../theme/koi_radii.dart';
import '../widgets/neo_button.dart';
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

/// The Care home. General: Find an Expert + My applications. Patient (an
/// active relationship confirmed by /me/capabilities): My Psychologist,
/// Questionnaires, Messages, Appointments, Notifications as well.
/// Pull-to-refresh re-checks the capabilities (General → Patient after an
/// accepted application, same uid, no sign-out).
class CareScreen extends ConsumerStatefulWidget {
  const CareScreen({super.key});

  /// MOB-1 placeholder text (no longer shown since MOB-2).
  static const String comingLater = 'Coming in a later update';

  @override
  ConsumerState<CareScreen> createState() => _CareScreenState();
}

class _CareScreenState extends ConsumerState<CareScreen> {
  Future<void> _refresh() async {
    await Future.wait([
      ref.read(capabilityControllerProvider).refresh(silent: true),
      ref.read(careSessionProvider).notifications.refresh(),
    ]);
  }

  @override
  Widget build(BuildContext context) => CapabilityGate(
    destination: KoiDestination.care,
    builder: (context) {
      final s = ref.watch(careStringsProvider);
      final caps = ref.watch(effectiveCapabilitiesProvider);
      final demo = ref.watch(capabilityControllerProvider).isMock;
      final session = ref.watch(careSessionProvider);
      final relationship = caps.relationship;
      final notice = session.notice;
      final unreadMessages = session.unreadMessageNotifications.length;
      return CarePage(
        back: false,
        demo: demo,
        title: s.t(CareText.care),
        onRefresh: _refresh,
        children: [
          if (notice != null) ...[
            KoiNoticeCard(
              key: const Key('care-notice'),
              yellow: true,
              message: s.t(notice),
              actionLabel: s.t(CareText.ok),
              action: session.clearNotice,
            ),
            const SizedBox(height: 16),
          ],
          if (caps.isPatient && relationship != null) ...[
            CareEntry(
              key: const Key('care-psychologist'),
              title: s.t(CareText.myPsychologist),
              subtitle:
                  ref
                      .watch(psychologistNameProvider(relationship))
                      .valueOrNull ??
                  s.t(CareText.yourPsychologist),
              onTap: () =>
                  pushKoiPage<void>(context, const MyPsychologistScreen()),
            ),
            if (caps.canUseQuestionnaires)
              CareEntry(
                key: const Key('care-questionnaires'),
                title: s.t(CareText.questionnaires),
                subtitle: s.t(CareText.questionnairesSub),
                onTap: () =>
                    pushKoiPage<void>(context, const QuestionnaireListScreen()),
              ),
            CareEntry(
              key: const Key('care-messages'),
              title: s.t(CareText.messages),
              subtitle: unreadMessages > 0
                  ? s.unreadCount(unreadMessages)
                  : s.t(CareText.messagesSub),
              onTap: () =>
                  pushKoiPage<void>(context, const ConversationListScreen()),
            ),
            CareEntry(
              key: const Key('care-appointments'),
              title: s.t(CareText.appointments),
              subtitle: s.t(CareText.appointmentsSub),
              onTap: () =>
                  pushKoiPage<void>(context, const AppointmentListScreen()),
            ),
          ],
          CareEntry(
            key: const Key('care-notifications'),
            title: s.t(CareText.notifications),
            subtitle: session.unreadCount > 0
                ? s.unreadCount(session.unreadCount)
                : s.t(CareText.notificationsSub),
            onTap: () =>
                pushKoiPage<void>(context, const NotificationInboxScreen()),
          ),
          if (caps.canDiscoverExperts) ...[
            CareEntry(
              key: const Key('care-experts'),
              title: s.t(CareText.findExpert),
              subtitle: s.t(CareText.findExpertSub),
              onTap: () => pushKoiPage<void>(context, const ExpertListScreen()),
            ),
            CareEntry(
              key: const Key('care-applications'),
              title: s.t(CareText.myApplications),
              subtitle: s.t(CareText.myApplicationsSub),
              onTap: () =>
                  pushKoiPage<void>(context, const MyApplicationsScreen()),
            ),
          ],
          if (ref.watch(simulatePsychologistMenuProvider))
            NeoButton(
              key: const Key('care-simulate'),
              variant: NeoButtonVariant.ghost,
              fullWidth: true,
              onPressed: () => showSimulatePsychologistMenu(context, ref),
              child: CareButtonLabel(s.t(CareText.simulateTitle)),
            ),
        ],
      );
    },
  );
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

/// The patient's relationship: the psychologist's directory name only.
class MyPsychologistScreen extends ConsumerWidget {
  const MyPsychologistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => CapabilityGate(
    destination: KoiDestination.myPsychologist,
    builder: (_) {
      final s = ref.watch(careStringsProvider);
      final rel = ref.watch(effectiveCapabilitiesProvider).relationship;
      final name = rel == null
          ? null
          : ref.watch(psychologistNameProvider(rel)).valueOrNull;
      return CarePage(
        demo: ref.watch(capabilityControllerProvider).isMock,
        title: s.t(CareText.myPsychologist),
        children: [
          NeoCard(
            padding: const EdgeInsets.all(18),
            child: Text(
              name ?? s.t(CareText.yourPsychologist),
              style: careBody(s, size: 18, weight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 20),
          KoiNoticeCard(yellow: true, message: s.t(CareText.notMonitored)),
        ],
      );
    },
  );
}
