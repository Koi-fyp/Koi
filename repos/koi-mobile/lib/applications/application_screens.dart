import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_providers.dart';
import '../account/account_widgets.dart';
import '../account/capabilities.dart';
import '../account/capability_gate.dart';
import '../account/destinations.dart';
import '../care/care_api_support.dart';
import '../care/care_providers.dart';
import '../care/care_strings.dart';
import '../care/care_widgets.dart';
import '../experts/expert_api.dart';
import '../widgets/neo_button.dart';
import '../widgets/neo_card.dart';
import 'application_flow.dart';
import 'application_labels.dart';
import 'application_models.dart';

/// "Payment: Pending / Confirmed (simulated)". A status label only: no
/// card field, no payment SDK, nothing that looks like a checkout.
String paymentLabel(CareStrings s, DemoPaymentState p) => s.t(
  p == DemoPaymentState.completed
      ? CareText.paymentConfirmed
      : CareText.paymentPending,
);

ApplicationFlow _flow(WidgetRef ref) {
  final session = ref.read(careSessionProvider);
  return ApplicationFlow(session.applicationApi, session.applications);
}

/// The psychologist's name for [uid] (directory), or "Your psychologist".
String _nameOf(WidgetRef ref, CareStrings s, String uid) =>
    ref
        .watch(
          psychologistNameProvider(
            RelationshipSummary(id: '', active: true, psychologistUid: uid),
          ),
        )
        .valueOrNull ??
    s.t(CareText.yourPsychologist);

/// "Apply to work with this psychologist": consent → confirm → send.
class ApplyScreen extends StatelessWidget {
  const ApplyScreen({super.key, required this.expert});
  final ExpertProfile expert;

  @override
  Widget build(BuildContext context) => CapabilityGate(
    destination: KoiDestination.applications,
    builder: (_) => _Apply(expert: expert),
  );
}

class _Apply extends ConsumerStatefulWidget {
  const _Apply({required this.expert});
  final ExpertProfile expert;

  @override
  ConsumerState<_Apply> createState() => _ApplyState();
}

class _ApplyState extends ConsumerState<_Apply> {
  bool _consent = false;
  bool _busy = false;
  bool _showConsentError = false;
  String? _error;

  // One "Send application" action = these two keys, reused on retry.
  final String _createKey = newIdempotencyKey();
  final String _continueKey = newIdempotencyKey();

  Future<void> _send() async {
    final s = ref.read(careStringsProvider);
    if (!_consent) {
      setState(() => _showConsentError = true);
      return;
    }
    final ok = await showCareConfirm(
      context,
      s,
      title: s.t(CareText.confirmTitle),
      body: s.t(CareText.confirmBody),
      yes: s.t(CareText.sendApplication),
      no: s.t(CareText.keep),
      yesKey: const Key('apply-confirm-send'),
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await runCareMutation(
        context,
        ref,
        () => _flow(ref).apply(
          widget.expert.id,
          createKey: _createKey,
          continueKey: _continueKey,
        ),
      );
      if (!mounted) return;
      unawaited(
        Navigator.of(context).pushReplacement(
          PageRouteBuilder<void>(
            transitionDuration: Duration.zero,
            pageBuilder: (_, _, _) => ApplicationDetailScreen(requestId: r.id),
          ),
        ),
      );
    } catch (e) {
      // A 403 also re-checks the capabilities, which can rebuild this page:
      // the Care home keeps the answer as its notice too.
      if (!mounted) return;
      if (careFailureOf(e) == CareFailure.denied) {
        ref.read(careSessionProvider).showNotice(CareText.m4NotAcceptingNow);
      }
      setState(() {
        _busy = false;
        _error = switch (careFailureOf(e)) {
          CareFailure.conflict => s.t(CareText.alreadyConnected),
          // v0.5.2 (lifecycle.ts:159-160): the profile is not discoverable
          // or not accepting new patients right now.
          CareFailure.denied => s.t(CareText.m4NotAcceptingNow),
          _ => careFailureText(s, e),
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(careStringsProvider);
    return CarePage(
      demo: ref.watch(applicationApiProvider).isMock,
      title: s.t(CareText.applyTitle),
      children: [
        Text(
          widget.expert.displayName,
          style: careBody(s, size: 18, weight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(s.t(CareText.applyIntro), style: careBody(s)),
        const SizedBox(height: 18),
        CareCheckRow(
          key: const Key('apply-consent'),
          strings: s,
          label: s.t(CareText.consentLabel),
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
        const SizedBox(height: 14),
        Text(s.t(CareText.paymentExplainer), style: careMuted(s)),
        if (_error != null) ...[
          const SizedBox(height: 12),
          KoiErrorText(_error!),
        ],
        const SizedBox(height: 20),
        CareActionButton(
          key: const Key('apply-continue'),
          label: s.t(CareText.continueLabel),
          busyLabel: s.t(CareText.sending),
          busy: _busy,
          onPressed: _send,
        ),
      ],
    );
  }
}

/// One application: status, simulated payment label, allowed actions.
class ApplicationDetailScreen extends StatelessWidget {
  const ApplicationDetailScreen({super.key, required this.requestId});
  final String requestId;

  @override
  Widget build(BuildContext context) => CapabilityGate(
    destination: KoiDestination.application,
    builder: (_) => _ApplicationDetail(requestId: requestId),
  );
}

class _ApplicationDetail extends ConsumerStatefulWidget {
  const _ApplicationDetail({required this.requestId});
  final String requestId;

  @override
  ConsumerState<_ApplicationDetail> createState() => _ApplicationDetailState();
}

class _ApplicationDetailState extends ConsumerState<_ApplicationDetail> {
  ApplicantAction? _running;
  String? _error;

  /// Keys of the action being tried, reused until it succeeds.
  final Map<ApplicantAction, String> _keys = {};

  @override
  void initState() {
    super.initState();
    unawaited(ref.read(careSessionProvider).applications.refresh());
  }

  Future<void> _run(ConnectionRequest r, ApplicantAction a) async {
    final s = ref.read(careStringsProvider);
    if (a == ApplicantAction.withdraw) {
      final ok = await showCareConfirm(
        context,
        s,
        title: s.t(CareText.withdrawTitle),
        body: s.t(CareText.withdrawBody),
        yes: s.t(CareText.withdrawYes),
        no: s.t(CareText.keep),
        yesKey: const Key('withdraw-confirm'),
      );
      if (!ok || !mounted) return;
    }
    final key = _keys.putIfAbsent(a, newIdempotencyKey);
    setState(() {
      _running = a;
      _error = null;
    });
    try {
      await runCareMutation(
        context,
        ref,
        () => _flow(ref).act(r, a, idempotencyKey: key),
      );
      _keys.remove(a);
    } catch (e) {
      if (mounted) setState(() => _error = careFailureText(s, e));
    }
    if (mounted) setState(() => _running = null);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(careStringsProvider);
    final list = ref.watch(careSessionProvider).applications;
    final r = list.items.where((a) => a.id == widget.requestId).firstOrNull;
    final demo = ref.watch(applicationApiProvider).isMock;
    if (r == null) {
      return CarePage(
        demo: demo,
        title: s.t(CareText.applicationTitle),
        onRefresh: list.refresh,
        children: careListStates<ConnectionRequest>(
          s: s,
          list: list,
          items: const [],
          loadingLabel: s.t(CareText.loading),
          emptyText: s.t(CareText.noLongerAvailable),
          item: (_) => const SizedBox.shrink(),
        ),
      );
    }
    final actions = applicantActions(r.state);
    final caps = ref.watch(effectiveCapabilitiesProvider);
    final note = applicationNote(r, caps);
    return CarePage(
      demo: demo,
      title: s.t(CareText.applicationTitle),
      onRefresh: list.refresh,
      children: [
        if (list.isUpdating) CareUpdating(strings: s),
        NeoCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _nameOf(ref, s, r.psychologistUid),
                style: careBody(s, size: 17, weight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              CareChip(
                key: const Key('application-state'),
                label: applicationLabel(s, r, caps),
                color: applicationChipColor(r, caps),
              ),
              const SizedBox(height: 8),
              Text(
                paymentLabel(s, r.demoPayment),
                key: const Key('application-payment'),
                style: careBody(s, size: 14, weight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                '${s.t(CareText.lastUpdated)}: ${s.dateTime(r.updatedAt)}',
                style: careMuted(s),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (note != null)
          KoiNoticeCard(
            key: const Key('application-note'),
            yellow: acceptedIntoActiveCare(r, caps),
            message: s.t(note),
          ),
        if (actions.contains(ApplicantAction.completeDemoPayment)) ...[
          Text(s.t(CareText.paymentExplainer), style: careMuted(s)),
          const SizedBox(height: 10),
        ],
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
          if (actions.contains(ApplicantAction.continueToPayment))
            _ActionPad(
              child: CareActionButton(
                key: const Key('application-continue'),
                label: s.t(CareText.continueLabel),
                busyLabel: s.t(CareText.sending),
                busy: false,
                onPressed: () => _run(r, ApplicantAction.continueToPayment),
              ),
            ),
          if (actions.contains(ApplicantAction.completeDemoPayment))
            _ActionPad(
              child: CareActionButton(
                key: const Key('application-demo-payment'),
                label: s.t(CareText.confirmDemoPayment),
                busyLabel: s.t(CareText.sending),
                busy: false,
                onPressed: () => _run(r, ApplicantAction.completeDemoPayment),
              ),
            ),
          if (actions.contains(ApplicantAction.withdraw))
            _ActionPad(
              child: CareActionButton(
                key: const Key('application-withdraw'),
                variant: NeoButtonVariant.ghost,
                label: s.t(CareText.withdraw),
                busyLabel: s.t(CareText.sending),
                busy: false,
                onPressed: () => _run(r, ApplicantAction.withdraw),
              ),
            ),
        ],
      ],
    );
  }
}

class _ActionPad extends StatelessWidget {
  const _ActionPad({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(bottom: 12), child: child);
}

/// "My applications": one status chip per application.
class MyApplicationsScreen extends StatelessWidget {
  const MyApplicationsScreen({super.key});

  @override
  Widget build(BuildContext context) => CapabilityGate(
    destination: KoiDestination.applications,
    builder: (_) => const _MyApplications(),
  );
}

class _MyApplications extends ConsumerStatefulWidget {
  const _MyApplications();

  @override
  ConsumerState<_MyApplications> createState() => _MyApplicationsState();
}

class _MyApplicationsState extends ConsumerState<_MyApplications> {
  @override
  void initState() {
    super.initState();
    unawaited(ref.read(careSessionProvider).applications.refresh());
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(careStringsProvider);
    final list = ref.watch(careSessionProvider).applications;
    final caps = ref.watch(effectiveCapabilitiesProvider);
    return CarePage(
      demo: ref.watch(applicationApiProvider).isMock,
      title: s.t(CareText.myApplications),
      onRefresh: list.refresh,
      children: careListStates<ConnectionRequest>(
        s: s,
        list: list,
        loadingLabel: s.t(CareText.loading),
        emptyText: s.t(CareText.noApplications),
        item: (r) => CareCard(
          key: Key('application-${r.id}'),
          onTap: () => pushKoiPage<void>(
            context,
            ApplicationDetailScreen(requestId: r.id),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _nameOf(ref, s, r.psychologistUid),
                style: careBody(s, size: 16, weight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              CareChip(
                label: applicationLabel(s, r, caps),
                color: applicationChipColor(r, caps),
              ),
              const SizedBox(height: 4),
              Text(paymentLabel(s, r.demoPayment), style: careMuted(s)),
            ],
          ),
        ),
      ),
    );
  }
}
