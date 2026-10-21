import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../applications/application_screens.dart';
import '../app/providers.dart';
import '../appointments/appointment_screens.dart';
import '../care/become_psychologist_screen.dart';
import '../care/care_hub.dart';
import '../care/care_providers.dart';
import '../care/care_strings.dart';
import '../care/care_widgets.dart';
import '../care/simulate_menu.dart';
import '../care_messages/message_screens.dart';
import '../experts/expert_screens.dart';
import '../invitations/invitation_screen.dart';
import '../notifications/notification_screens.dart';
import '../questionnaires/questionnaire_providers.dart';
import '../theme/koi_colors.dart';
import '../theme/koi_radii.dart';
import '../widgets/neo_button.dart';
import '../widgets/neo_card.dart';
import 'account_providers.dart';
import 'account_widgets.dart';
import 'auth_entry_widgets.dart';
import 'capability_controller.dart';
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
      pageBuilder: (context, _, _) => const CareHome(),
    ),
  );
}

/// The first page of the Care tab (AUTH-ENTRY): the information page for
/// an anonymous user, "not available yet" while a registered account's
/// features cannot be confirmed, "not set up yet" (MOB-4) when the server
/// confirms no Care area, otherwise the Care home.
class CareHome extends ConsumerWidget {
  const CareHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authServiceProvider).user;
    if (user == null || user.isAnonymous) return const AnonymousCareScreen();
    final controller = ref.watch(capabilityControllerProvider);
    if (controller.status == CapabilityStatus.unavailable) {
      return const CareUnavailableScreen();
    }
    if (controller.effective.careNotSetUp) return const CareNotSetUpScreen();
    return const CareScreen();
  }
}

/// The Care home (MOB-5: two hubs, like the web's General User and Patient
/// dashboards on origin/feat/koi2-ui-overhaul f9ed940):
/// - Care Home (General): Find a Psychologist, My Applications,
///   Notifications, invitation code, Become a Psychologist (info only);
/// - My Care (Patient, an active relationship confirmed by
///   /me/capabilities): My Psychologist, Questionnaires, Messages,
///   Appointments, Notifications, and the General entries under
///   "Additional care options".
/// The hub follows the confirmed capabilities only, so an accepted
/// application turns Care Home into My Care with no extra step, and a
/// closed relationship turns it back. Pull-to-refresh re-checks them.
class CareScreen extends ConsumerStatefulWidget {
  const CareScreen({super.key});

  /// MOB-1 placeholder text (no longer shown since MOB-2).
  static const String comingLater = 'Coming in a later update';

  @override
  ConsumerState<CareScreen> createState() => _CareScreenState();
}

class _CareScreenState extends ConsumerState<CareScreen> {
  Future<void> _refresh() async {
    if (ref.read(effectiveCapabilitiesProvider).canUseQuestionnaires) {
      ref.invalidate(assignmentsProvider);
    }
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
      final controller = ref.watch(capabilityControllerProvider);
      final session = ref.watch(careSessionProvider);
      final patient = caps.isPatient;
      final relationship = caps.relationship;
      final notice = session.notice;
      final unreadMessages = session.unreadMessageNotifications.length;
      void open(Widget page) => pushKoiPage<void>(context, page);

      final notifications = CareEntry(
        key: const Key('care-notifications'),
        title: s.t(CareText.notifications),
        subtitle: session.unreadCount > 0
            ? s.unreadCount(session.unreadCount)
            : s.t(CareText.notificationsSub),
        onTap: () => open(const NotificationInboxScreen()),
      );
      final applications = CareEntry(
        key: const Key('care-applications'),
        title: s.t(CareText.myApplications),
        subtitle: s.t(CareText.myApplicationsSub),
        onTap: () => open(const MyApplicationsScreen()),
      );
      // MOB-4: General / Patient only (this page needs a confirmed Care
      // area); "not set up yet" accounts never see it.
      final invitation = CareEntry(
        key: const Key('care-invitation'),
        title: s.t(CareText.m4InviteEntry),
        subtitle: s.t(CareText.m4InviteEntrySub),
        onTap: () => open(const InvitationScreen()),
      );
      final become = CareEntry(
        key: const Key('care-become-psychologist'),
        title: s.t(CareText.m5BecomeTitle),
        subtitle: s.t(CareText.m5BecomeSub),
        onTap: () => open(const BecomePsychologistScreen()),
      );

      return CarePage(
        key: Key(patient ? 'my-care-hub' : 'care-home-hub'),
        back: false,
        demo: controller.isMock,
        title: s.t(patient ? CareText.m5MyCare : CareText.m5CareHome),
        onRefresh: _refresh,
        children: [
          CareRoleChip(
            label: s.t(
              patient ? CareText.m5RolePatient : CareText.m5RoleGeneral,
            ),
          ),
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
          if (patient) ...[
            CareHeroCard(
              key: const Key('care-hero'),
              strings: s,
              title: s.t(CareText.m5ActiveTitle),
              eyebrow: s.t(CareText.m5Connected),
              body:
                  (relationship == null
                      ? null
                      : ref
                            .watch(psychologistNameProvider(relationship))
                            .valueOrNull) ??
                  s.t(CareText.yourPsychologist),
              actions: [
                CareActionButton(
                  key: const Key('care-psychologist'),
                  label: s.t(CareText.myPsychologist),
                  busyLabel: '',
                  busy: false,
                  onPressed: () => open(const MyPsychologistScreen()),
                ),
                CareActionButton(
                  key: const Key('care-hero-messages'),
                  variant: NeoButtonVariant.secondary,
                  label: s.t(CareText.m5OpenMessages),
                  busyLabel: '',
                  busy: false,
                  onPressed: () => open(const ConversationListScreen()),
                ),
              ],
            ),
            if (caps.canUseQuestionnaires) const MyCareQuestionnairesCard(),
            CareEntry(
              key: const Key('care-messages'),
              title: s.t(CareText.messages),
              subtitle: unreadMessages > 0
                  ? s.unreadCount(unreadMessages)
                  : s.t(CareText.messagesSub),
              onTap: () => open(const ConversationListScreen()),
            ),
            CareEntry(
              key: const Key('care-appointments'),
              title: s.t(CareText.appointments),
              subtitle: s.t(CareText.appointmentsSub),
              onTap: () => open(const AppointmentListScreen()),
            ),
            notifications,
            MoreCareOptions(
              strings: s,
              children: [
                if (caps.canDiscoverExperts) ...[
                  CareEntry(
                    key: const Key('care-experts'),
                    title: s.t(CareText.findExpert),
                    subtitle: s.t(CareText.findExpertSub),
                    onTap: () => open(const ExpertListScreen()),
                  ),
                  applications,
                ],
                invitation,
                become,
              ],
            ),
          ] else ...[
            if (controller.endedNotice) ...[
              KoiNoticeCard(
                key: const Key('care-ended-notice'),
                yellow: true,
                message: s.t(CareText.m5Ended),
                actionLabel: s.t(CareText.ok),
                action: controller.dismissEndedNotice,
              ),
              const SizedBox(height: 16),
            ],
            if (caps.canDiscoverExperts) ...[
              CareHeroCard(
                key: const Key('care-hero'),
                strings: s,
                title: s.t(CareText.m5StartTitle),
                body: s.t(CareText.m5StartBody),
                actions: [
                  CareActionButton(
                    key: const Key('care-experts'),
                    label: s.t(CareText.findExpert),
                    busyLabel: '',
                    busy: false,
                    onPressed: () => open(const ExpertListScreen()),
                  ),
                ],
              ),
              applications,
            ],
            notifications,
            invitation,
            become,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name ?? s.t(CareText.yourPsychologist),
                  style: careBody(s, size: 18, weight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                // MOB-5: PatientWorkspace.tsx "My Psychologist" card.
                Text(s.t(CareText.m5PsyAccess), style: careBody(s)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CareEntry(
            key: const Key('mypsy-messages'),
            title: s.t(CareText.m5MessageTeam),
            subtitle: s.t(CareText.messagesSub),
            onTap: () =>
                pushKoiPage<void>(context, const ConversationListScreen()),
          ),
          CareEntry(
            key: const Key('mypsy-appointments'),
            title: s.t(CareText.m5ManageAppointments),
            subtitle: s.t(CareText.appointmentsSub),
            onTap: () =>
                pushKoiPage<void>(context, const AppointmentListScreen()),
          ),
          KoiNoticeCard(yellow: true, message: s.t(CareText.notMonitored)),
        ],
      );
    },
  );
}
