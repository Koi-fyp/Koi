import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_providers.dart';
import '../account/account_widgets.dart';
import '../account/capabilities.dart';
import '../account/capability_controller.dart';
import '../account/capability_gate.dart';
import '../account/destinations.dart';
import '../applications/application_screens.dart';
import '../appointments/appointment_screens.dart';
import '../care/care_api_support.dart';
import '../care/care_providers.dart';
import '../care/care_strings.dart';
import '../care/care_widgets.dart';
import '../care_messages/message_screens.dart';
import '../questionnaires/questionnaire_screens.dart';
import '../theme/koi_colors.dart';
import '../widgets/neo_button.dart';
import 'notification_models.dart';

/// The app's fixed wording per kind: notifications carry no text, and
/// never a score, result or evaluation.
String notificationText(CareStrings s, NotificationKind k) => s.t(switch (k) {
  NotificationKind.assignment => CareText.kindAssignment,
  NotificationKind.newMessage => CareText.kindNewMessage,
  NotificationKind.appointmentChange => CareText.kindAppointment,
  NotificationKind.applicationState => CareText.kindApplication,
});

/// Where a notification leads, re-checked against the CURRENT
/// capabilities. `page == null` means the target is no longer accessible
/// (relationship ended, access revoked): show a friendly message instead.
({KoiDestination destination, Widget? page}) notificationTarget(
  CareNotification n, {
  required CapabilityStatus status,
  required KoiCapabilities caps,
}) {
  final rel = caps.activeRelationships.firstOrNull;
  final (KoiDestination d, Widget? page) = switch (n.kind) {
    NotificationKind.assignment => (
      KoiDestination.questionnaires,
      const QuestionnaireListScreen(),
    ),
    NotificationKind.newMessage => (
      KoiDestination.messageThread,
      rel == null ? null : MessageThreadScreen(relationshipId: rel.id),
    ),
    NotificationKind.appointmentChange => (
      KoiDestination.appointment,
      rel == null
          ? null
          : AppointmentDetailScreen(
              relationshipId: rel.id,
              appointmentId: n.referenceId,
            ),
    ),
    NotificationKind.applicationState => (
      KoiDestination.application,
      ApplicationDetailScreen(requestId: n.referenceId),
    ),
  };
  final allowed =
      decideDestination(d, status: status, caps: caps) == LinkDecision.allow;
  return (destination: d, page: allowed ? page : null);
}

class NotificationInboxScreen extends StatelessWidget {
  const NotificationInboxScreen({super.key});

  @override
  Widget build(BuildContext context) => CapabilityGate(
    destination: KoiDestination.notifications,
    builder: (_) => const _Inbox(),
  );
}

class _Inbox extends ConsumerStatefulWidget {
  const _Inbox();

  @override
  ConsumerState<_Inbox> createState() => _InboxState();
}

class _InboxState extends ConsumerState<_Inbox> {
  bool _markingAll = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    unawaited(ref.read(careSessionProvider).notifications.refresh());
  }

  Future<void> _open(CareNotification n) async {
    final s = ref.read(careStringsProvider);
    final session = ref.read(careSessionProvider);
    unawaited(session.markRead(n));
    final controller = ref.read(capabilityControllerProvider);
    final target = notificationTarget(
      n,
      status: controller.status,
      caps: controller.effective,
    );
    final page = target.page;
    if (page == null) {
      setState(() => _notice = s.t(CareText.noLongerAvailable));
      return;
    }
    setState(() => _notice = null);
    await pushKoiPage<void>(context, page);
  }

  Future<void> _markAll() async {
    final s = ref.read(careStringsProvider);
    setState(() {
      _markingAll = true;
      _notice = null;
    });
    final f = await ref.read(careSessionProvider).markAllRead();
    if (!mounted) return;
    setState(() {
      _markingAll = false;
      if (f != null) _notice = careFailureText(s, f);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(careStringsProvider);
    final session = ref.watch(careSessionProvider);
    final list = session.notifications;
    return CarePage(
      demo: ref.watch(notificationApiProvider).isMock,
      title: s.t(CareText.notifications),
      onRefresh: list.refresh,
      children: [
        if (_notice != null) ...[
          KoiNoticeCard(
            key: const Key('notification-notice'),
            yellow: true,
            message: _notice!,
          ),
          const SizedBox(height: 14),
        ],
        if (session.unreadCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: CareActionButton(
              key: const Key('notifications-mark-all'),
              variant: NeoButtonVariant.ghost,
              label: s.t(CareText.markAllRead),
              busyLabel: s.t(CareText.updating),
              busy: _markingAll,
              onPressed: _markAll,
            ),
          ),
        ...careListStates<CareNotification>(
          s: s,
          list: list,
          loadingLabel: s.t(CareText.loading),
          emptyText: s.t(CareText.noNotifications),
          item: (n) => CareCard(
            key: Key('notification-${n.id}'),
            semanticsLabel: [
              notificationText(s, n.kind),
              if (!n.isRead) s.t(CareText.unread),
            ].join('. '),
            onTap: () => _open(n),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notificationText(s, n.kind),
                        style: careBody(
                          s,
                          size: 15.5,
                          weight: n.isRead ? FontWeight.w500 : FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(s.dateTime(n.createdAt), style: careMuted(s, 12.5)),
                    ],
                  ),
                ),
                if (!n.isRead)
                  Container(
                    key: const Key('notification-unread-dot'),
                    width: 14,
                    height: 14,
                    margin: const EdgeInsetsDirectional.only(start: 8),
                    decoration: BoxDecoration(
                      color: KoiColors.neoBlue,
                      shape: BoxShape.circle,
                      border: Border.all(width: 2),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
