import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_providers.dart';
import '../account/account_widgets.dart';
import '../account/capability_gate.dart';
import '../account/destinations.dart';
import '../care/care_api_support.dart';
import '../care/care_providers.dart';
import '../care/care_session.dart';
import '../care/care_strings.dart';
import '../care/care_widgets.dart';
import '../theme/koi_colors.dart';
import '../widgets/neo_button.dart';
import '../widgets/neo_card.dart';
import 'appointment_models.dart';

String appointmentStateLabel(CareStrings s, AppointmentState st) =>
    s.t(switch (st) {
      AppointmentState.requested => CareText.apptRequested,
      AppointmentState.proposed => CareText.apptProposed,
      AppointmentState.confirmed => CareText.apptConfirmed,
      AppointmentState.completed => CareText.apptCompleted,
      AppointmentState.rejected => CareText.apptRejected,
      AppointmentState.cancelled => CareText.apptCancelled,
    });

Color appointmentChipColor(AppointmentState st) => switch (st) {
  AppointmentState.confirmed => KoiColors.neoMint,
  AppointmentState.requested ||
  AppointmentState.proposed => KoiColors.neoYellow,
  _ => KoiColors.neoGray,
};

String sectionLabel(CareStrings s, AppointmentSection x) => s.t(switch (x) {
  AppointmentSection.upcoming => CareText.upcoming,
  AppointmentSection.pending => CareText.pending,
  AppointmentSection.past => CareText.past,
  AppointmentSection.cancelled => CareText.cancelled,
});

/// The first active relationship (the Care area shows one psychologist).
String? _relationshipId(WidgetRef ref) => ref
    .watch(effectiveCapabilitiesProvider)
    .activeRelationships
    .firstOrNull
    ?.id;

class AppointmentListScreen extends StatelessWidget {
  const AppointmentListScreen({super.key});

  @override
  Widget build(BuildContext context) => CapabilityGate(
    destination: KoiDestination.appointments,
    builder: (_) => const _AppointmentList(),
  );
}

class _AppointmentList extends ConsumerStatefulWidget {
  const _AppointmentList();

  @override
  ConsumerState<_AppointmentList> createState() => _AppointmentListState();
}

class _AppointmentListState extends ConsumerState<_AppointmentList> {
  bool _requesting = false;
  String? _error;
  String? _requestKey;

  @override
  void initState() {
    super.initState();
    final rel = ref
        .read(effectiveCapabilitiesProvider)
        .activeRelationships
        .firstOrNull;
    if (rel != null) {
      unawaited(
        ref.read(careSessionProvider).appointmentsFor(rel.id).refresh(),
      );
    }
  }

  Future<void> _request(
    String relationshipId,
    CareList<Appointment> list,
  ) async {
    final s = ref.read(careStringsProvider);
    final key = _requestKey ??= newIdempotencyKey();
    setState(() {
      _requesting = true;
      _error = null;
    });
    try {
      final a = await runCareMutation(
        context,
        ref,
        () => ref
            .read(careSessionProvider)
            .appointmentApi
            .request(relationshipId, idempotencyKey: key),
      );
      list.put(a);
      _requestKey = null;
    } catch (e) {
      if (mounted) setState(() => _error = careFailureText(s, e));
    }
    if (mounted) setState(() => _requesting = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(careStringsProvider);
    final relId = _relationshipId(ref);
    final demo = ref.watch(appointmentApiProvider).isMock;
    if (relId == null) {
      return CarePage(
        demo: demo,
        title: s.t(CareText.appointments),
        children: [KoiNoticeCard(message: s.t(CareText.noLongerAvailable))],
      );
    }
    final session = ref.watch(careSessionProvider);
    final list = session.appointmentsFor(relId);
    final bySection = {
      for (final x in AppointmentSection.values)
        x: [
          for (final a in list.items)
            if (sectionOf(a) == x) a,
        ],
    };
    return CarePage(
      demo: demo,
      title: s.t(CareText.appointments),
      onRefresh: list.refresh,
      children: [
        Text(s.t(CareText.requestExplainer), style: careBody(s)),
        const SizedBox(height: 12),
        if (_error != null) ...[
          KoiErrorText(_error!),
          const SizedBox(height: 10),
        ],
        CareActionButton(
          key: const Key('appointment-request'),
          label: s.t(CareText.requestAppointment),
          busyLabel: s.t(CareText.requesting),
          busy: _requesting,
          onPressed: () => _request(relId, list),
        ),
        const SizedBox(height: 20),
        // MOB-4: every page is read; past 1,000 it says so.
        if (list.capped) ...[
          Text(
            s.t(CareText.m4AppointmentsCapped),
            key: const Key('appointments-capped'),
            style: careMuted(s),
          ),
          const SizedBox(height: 12),
        ],
        ...careListStates<AppointmentSection>(
          s: s,
          list: list,
          items: list.items.isEmpty
              ? const []
              : [
                  for (final x in AppointmentSection.values)
                    if (bySection[x]!.isNotEmpty) x,
                ],
          loadingLabel: s.t(CareText.loading),
          emptyText: s.t(CareText.noAppointments),
          item: (x) => Column(
            key: Key('appointment-section-${x.name}'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  sectionLabel(s, x),
                  style: careBody(s, size: 17, weight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 8),
              for (final a in bySection[x]!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _AppointmentCard(appointment: a, strings: s),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({required this.appointment, required this.strings});
  final Appointment appointment;
  final CareStrings strings;

  @override
  Widget build(BuildContext context) {
    final s = strings;
    final a = appointment;
    return CareCard(
      key: Key('appointment-${a.id}'),
      onTap: () => pushKoiPage<void>(
        context,
        AppointmentDetailScreen(
          relationshipId: a.relationshipId,
          appointmentId: a.id,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.timeRange(a.startsAt, a.endsAt),
            style: careBody(s, size: 16, weight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          CareChip(
            label: appointmentStateLabel(s, a.state),
            color: appointmentChipColor(a.state),
          ),
        ],
      ),
    );
  }
}

class AppointmentDetailScreen extends StatelessWidget {
  const AppointmentDetailScreen({
    super.key,
    required this.relationshipId,
    required this.appointmentId,
  });

  final String relationshipId;
  final String appointmentId;

  @override
  Widget build(BuildContext context) => CapabilityGate(
    destination: KoiDestination.appointment,
    builder: (_) => _AppointmentDetail(
      relationshipId: relationshipId,
      appointmentId: appointmentId,
    ),
  );
}

class _AppointmentDetail extends ConsumerStatefulWidget {
  const _AppointmentDetail({
    required this.relationshipId,
    required this.appointmentId,
  });

  final String relationshipId;
  final String appointmentId;

  @override
  ConsumerState<_AppointmentDetail> createState() => _AppointmentDetailState();
}

class _AppointmentDetailState extends ConsumerState<_AppointmentDetail> {
  PatientAppointmentAction? _running;
  String? _error;
  final Map<PatientAppointmentAction, String> _keys = {};

  @override
  void initState() {
    super.initState();
    final list = ref
        .read(careSessionProvider)
        .appointmentsFor(widget.relationshipId);
    unawaited(list.refresh());
  }

  Future<void> _run(Appointment a, PatientAppointmentAction action) async {
    final s = ref.read(careStringsProvider);
    if (!patientAppointmentActions(a).contains(action)) return;
    if (action == PatientAppointmentAction.cancel) {
      final ok = await showCareConfirm(
        context,
        s,
        title: s.t(CareText.cancelTitle),
        body: s.t(CareText.cancelBody),
        yes: s.t(CareText.cancelYes),
        no: s.t(CareText.keep),
        yesKey: const Key('appointment-cancel-confirm'),
      );
      if (!ok || !mounted) return;
    }
    if (action == PatientAppointmentAction.askAnotherTime) {
      final ok = await showCareConfirm(
        context,
        s,
        title: s.t(CareText.askAnotherTime),
        body: s.t(CareText.askAnotherTimeBody),
        yes: s.t(CareText.requestAppointment),
        no: s.t(CareText.keep),
        yesKey: const Key('appointment-ask-confirm'),
      );
      if (!ok || !mounted) return;
    }
    final key = _keys.putIfAbsent(action, newIdempotencyKey);
    final session = ref.read(careSessionProvider);
    final list = session.appointmentsFor(widget.relationshipId);
    setState(() {
      _running = action;
      _error = null;
    });
    try {
      final result = await runCareMutation(context, ref, () {
        switch (action) {
          case PatientAppointmentAction.confirm:
            checkPatientTransition(a.state, AppointmentState.confirmed);
            return session.appointmentApi.transition(
              a.id,
              expectedRevision: a.revision,
              to: AppointmentState.confirmed,
              idempotencyKey: key,
            );
          case PatientAppointmentAction.cancel:
            checkPatientTransition(a.state, AppointmentState.cancelled);
            return session.appointmentApi.transition(
              a.id,
              expectedRevision: a.revision,
              to: AppointmentState.cancelled,
              idempotencyKey: key,
            );
          case PatientAppointmentAction.askAnotherTime:
            return session.appointmentApi.request(
              widget.relationshipId,
              idempotencyKey: key,
            );
        }
      });
      // Only the server's answer is shown.
      list.put(result);
      _keys.remove(action);
    } catch (e) {
      if (mounted) setState(() => _error = careFailureText(s, e));
    }
    if (mounted) setState(() => _running = null);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(careStringsProvider);
    final list = ref
        .watch(careSessionProvider)
        .appointmentsFor(widget.relationshipId);
    final a = list.items.where((x) => x.id == widget.appointmentId).firstOrNull;
    final demo = ref.watch(appointmentApiProvider).isMock;
    if (a == null) {
      return CarePage(
        demo: demo,
        title: s.t(CareText.appointmentTitle),
        onRefresh: list.refresh,
        children: [
          if (list.isLoading || list.isUpdating)
            CareUpdating(strings: s)
          else
            KoiNoticeCard(message: s.t(CareText.noLongerAvailable)),
        ],
      );
    }
    final actions = patientAppointmentActions(a);
    return CarePage(
      demo: demo,
      title: s.t(CareText.appointmentTitle),
      onRefresh: list.refresh,
      children: [
        if (list.isUpdating) CareUpdating(strings: s),
        NeoCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.timeRange(a.startsAt, a.endsAt),
                key: const Key('appointment-time'),
                style: careBody(s, size: 17, weight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              CareChip(
                key: const Key('appointment-state'),
                label: appointmentStateLabel(s, a.state),
                color: appointmentChipColor(a.state),
              ),
              const SizedBox(height: 8),
              // The contract has no status history; only the last change.
              Text(
                '${s.t(CareText.lastUpdated)}: ${s.dateTime(a.updatedAt)}',
                style: careMuted(s),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (_error != null) ...[
          KoiErrorText(_error!),
          const SizedBox(height: 12),
        ],
        if (_running != null)
          CareActionButton(
            label: '',
            busyLabel: s.t(CareText.sending),
            busy: true,
            onPressed: null,
          )
        else ...[
          if (actions.contains(PatientAppointmentAction.confirm))
            _Pad(
              CareActionButton(
                key: const Key('appointment-confirm'),
                label: s.t(CareText.confirmTime),
                busyLabel: s.t(CareText.sending),
                busy: false,
                onPressed: () => _run(a, PatientAppointmentAction.confirm),
              ),
            ),
          if (actions.contains(PatientAppointmentAction.askAnotherTime))
            _Pad(
              CareActionButton(
                key: const Key('appointment-ask-another'),
                variant: NeoButtonVariant.ghost,
                label: s.t(CareText.askAnotherTime),
                busyLabel: s.t(CareText.sending),
                busy: false,
                onPressed: () =>
                    _run(a, PatientAppointmentAction.askAnotherTime),
              ),
            ),
          if (actions.contains(PatientAppointmentAction.cancel))
            _Pad(
              CareActionButton(
                key: const Key('appointment-cancel'),
                variant: NeoButtonVariant.ghost,
                label: a.state == AppointmentState.proposed
                    ? s.t(CareText.decline)
                    : s.t(CareText.cancelAppointment),
                busyLabel: s.t(CareText.sending),
                busy: false,
                onPressed: () => _run(a, PatientAppointmentAction.cancel),
              ),
            ),
        ],
      ],
    );
  }
}

class _Pad extends StatelessWidget {
  const _Pad(this.child);
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(bottom: 12), child: child);
}
