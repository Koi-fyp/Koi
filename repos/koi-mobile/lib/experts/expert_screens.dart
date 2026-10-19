import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_providers.dart';
import '../account/account_widgets.dart';
import '../account/capability_gate.dart';
import '../account/destinations.dart';
import '../applications/application_models.dart';
import '../applications/application_screens.dart';
import '../care/care_api_support.dart';
import '../care/care_providers.dart';
import '../care/care_strings.dart';
import '../care/care_widgets.dart';
import '../platform/platform_client.dart';
import '../theme/koi_colors.dart';
import '../widgets/koi_loader.dart';
import '../widgets/neo_card.dart';
import '../widgets/neo_input.dart';
import 'expert_api.dart';

/// One profile, per signed-in uid (rebuilt on account switch). Watches only
/// the discovery flag, so a capability re-check with the same answer does
/// not fetch again.
final expertDetailProvider = FutureProvider.autoDispose
    .family<ExpertProfile, String>((ref, id) {
      ref.watch(careUidProvider);
      final allowed = ref.watch(
        effectiveCapabilitiesProvider.select((c) => c.canDiscoverExperts),
      );
      if (!allowed) throw const PlatformException(PlatformErrorCode.forbidden);
      return ref.watch(expertDirectoryApiProvider).detail(id);
    });

/// MOB-1 error wording, still used by the questionnaire screens (unchanged
/// in MOB-2; the Care screens use careFailureText).
String platformErrorText(Object e) => switch (e) {
  PlatformException(code: PlatformErrorCode.notConfigured) =>
    'This is not available in this version of the app yet.',
  PlatformException(code: PlatformErrorCode.network) ||
  PlatformException(
    code: PlatformErrorCode.timeout,
  ) => 'You seem to be offline. Check your connection and try again.',
  PlatformException(code: PlatformErrorCode.forbidden) =>
    CapabilityGate.deniedText,
  PlatformException(code: PlatformErrorCode.notFound) =>
    'This is no longer available.',
  _ => 'Something went wrong. Please try again.',
};

/// Search waits this long after the last keystroke.
const Duration expertSearchDebounce = Duration(milliseconds: 300);

/// Client-side filter over the LOADED pages: the contract's directory has
/// only `limit` / `cursor` (decision C: no specialty / language /
/// availability filters exist).
List<ExpertProfile> filterExperts(
  List<ExpertProfile> all, {
  String query = '',
  bool acceptingOnly = false,
}) {
  final q = query.trim().toLowerCase();
  return [
    for (final e in all)
      if ((q.isEmpty || e.displayName.toLowerCase().contains(q)) &&
          (!acceptingOnly || e.acceptingNewPatients))
        e,
  ];
}

/// "Find an Expert".
class ExpertListScreen extends StatelessWidget {
  const ExpertListScreen({super.key});

  @override
  Widget build(BuildContext context) => CapabilityGate(
    destination: KoiDestination.experts,
    builder: (_) => const _ExpertList(),
  );
}

class _ExpertList extends ConsumerStatefulWidget {
  const _ExpertList();

  @override
  ConsumerState<_ExpertList> createState() => _ExpertListState();
}

class _ExpertListState extends ConsumerState<_ExpertList> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  String _query = '';
  bool _acceptingOnly = false;

  @override
  void initState() {
    super.initState();
    final list = ref.read(careSessionProvider).experts;
    unawaited(list.refresh());
    _scroll.addListener(() {
      // Lazy loading: the next page when the end comes into view.
      if (_scroll.position.extentAfter < 300) {
        unawaited(ref.read(careSessionProvider).experts.loadMore());
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(expertSearchDebounce, () {
      if (mounted) setState(() => _query = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(careStringsProvider);
    final session = ref.watch(careSessionProvider);
    final list = session.experts;
    final shown = filterExperts(
      list.items,
      query: _query,
      acceptingOnly: _acceptingOnly,
    );
    final filtering = _query.trim().isNotEmpty || _acceptingOnly;
    return CarePage(
      demo: ref.watch(expertDirectoryApiProvider).isMock,
      title: s.t(CareText.findExpert),
      controller: _scroll,
      onRefresh: list.refresh,
      children: [
        Text(s.t(CareText.expertsIntro), style: careBody(s)),
        const SizedBox(height: 16),
        NeoInput(
          key: const Key('expert-search'),
          label: s.t(CareText.searchLabel),
          controller: _search,
          onChanged: _onSearch,
        ),
        const SizedBox(height: 8),
        CareCheckRow(
          key: const Key('expert-accepting-only'),
          strings: s,
          label: s.t(CareText.acceptingOnly),
          checked: _acceptingOnly,
          onChanged: () => setState(() => _acceptingOnly = !_acceptingOnly),
        ),
        const SizedBox(height: 12),
        ...careListStates<ExpertProfile>(
          s: s,
          list: list,
          items: shown,
          loadingLabel: s.t(CareText.loading),
          emptyText: filtering && list.items.isNotEmpty
              ? s.t(CareText.noMatches)
              : s.t(CareText.noExperts),
          item: (e) => _ExpertCard(expert: e, strings: s),
        ),
      ],
    );
  }
}

class _ExpertCard extends StatelessWidget {
  const _ExpertCard({required this.expert, required this.strings});
  final ExpertProfile expert;
  final CareStrings strings;

  @override
  Widget build(BuildContext context) {
    final s = strings;
    return CareCard(
      key: Key('expert-${expert.id}'),
      semanticsLabel: expert.displayName,
      onTap: () =>
          pushKoiPage<void>(context, ExpertDetailScreen(expertId: expert.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            expert.displayName,
            style: careBody(s, size: 17, weight: FontWeight.w700),
          ),
          if (expert.bio.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              expert.bio,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: careMuted(s),
            ),
          ],
          const SizedBox(height: 6),
          CareChip(
            label: expert.acceptingNewPatients
                ? s.t(CareText.accepting)
                : s.t(CareText.notAccepting),
            color: expert.acceptingNewPatients
                ? KoiColors.neoMint
                : KoiColors.neoGray,
          ),
        ],
      ),
    );
  }
}

class ExpertDetailScreen extends StatelessWidget {
  const ExpertDetailScreen({super.key, required this.expertId});
  final String expertId;

  @override
  Widget build(BuildContext context) => CapabilityGate(
    destination: KoiDestination.expert,
    builder: (_) => _ExpertDetail(expertId: expertId),
  );
}

class _ExpertDetail extends ConsumerStatefulWidget {
  const _ExpertDetail({required this.expertId});
  final String expertId;

  @override
  ConsumerState<_ExpertDetail> createState() => _ExpertDetailState();
}

class _ExpertDetailState extends ConsumerState<_ExpertDetail> {
  @override
  void initState() {
    super.initState();
    // The applicant's own requests decide what Apply does.
    final apps = ref.read(careSessionProvider).applications;
    if (!apps.loaded) unawaited(apps.refresh());
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(careStringsProvider);
    final detail = ref.watch(expertDetailProvider(widget.expertId));
    final demo = ref.watch(expertDirectoryApiProvider).isMock;
    return detail.when(
      loading: () => Directionality(
        textDirection: s.direction,
        child: Scaffold(body: KoiLoadingPage(label: s.t(CareText.loading))),
      ),
      error: (e, _) => CarePage(
        demo: demo,
        children: [
          KoiNoticeCard(
            message: careFailureText(s, e),
            action: careFailureOf(e) == CareFailure.notAvailable
                ? null
                : () => ref.invalidate(expertDetailProvider(widget.expertId)),
            actionLabel: s.t(CareText.retry),
          ),
        ],
      ),
      data: (e) => CarePage(
        demo: demo,
        title: e.displayName,
        children: [
          if (e.bio.isNotEmpty) ...[
            Text(e.bio, style: careBody(s)),
            const SizedBox(height: 16),
          ],
          NeoCard(
            padding: const EdgeInsets.all(16),
            child: Text(
              e.acceptingNewPatients
                  ? s.t(CareText.accepting)
                  : s.t(CareText.notAccepting),
              style: careBody(s, size: 14.5, weight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 20),
          _ApplySection(expert: e, strings: s),
        ],
      ),
    );
  }
}

/// What the profile offers: Apply, or why not (one active application per
/// psychologist, already connected, applied before, not accepting).
class _ApplySection extends ConsumerWidget {
  const _ApplySection({required this.expert, required this.strings});
  final ExpertProfile expert;
  final CareStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = strings;
    final caps = ref.watch(effectiveCapabilitiesProvider);
    final apps = ref.watch(careSessionProvider).applications;
    final guard = applyGuard(
      expert,
      applications: apps.items,
      connectedPsychologists: {
        for (final r in caps.activeRelationships) r.psychologistUid,
      },
    );
    if (apps.isLoading) {
      return KoiLoader(compact: true, label: s.t(CareText.loading));
    }
    final existing = guard.existing;
    return switch (guard.kind) {
      ApplyGuardKind.canApply => CareActionButton(
        key: const Key('expert-apply'),
        label: s.t(CareText.apply),
        busyLabel: s.t(CareText.sending),
        busy: false,
        onPressed: () =>
            pushKoiPage<void>(context, ApplyScreen(expert: expert)),
      ),
      ApplyGuardKind.alreadyConnected => KoiNoticeCard(
        key: const Key('expert-already-connected'),
        yellow: true,
        message: s.t(CareText.alreadyConnected),
      ),
      ApplyGuardKind.activeApplication => KoiNoticeCard(
        key: const Key('expert-active-application'),
        yellow: true,
        message: s.t(CareText.statePendingReview),
        actionLabel: s.t(CareText.viewApplication),
        action: () => pushKoiPage<void>(
          context,
          ApplicationDetailScreen(requestId: existing!.id),
        ),
      ),
      ApplyGuardKind.appliedBefore => KoiNoticeCard(
        key: const Key('expert-applied-before'),
        yellow: true,
        message: s.t(CareText.appliedBefore),
      ),
      ApplyGuardKind.notAccepting => KoiNoticeCard(
        key: const Key('expert-not-accepting'),
        yellow: true,
        message: s.t(CareText.notAcceptingCantApply),
      ),
    };
  }
}

enum ApplyGuardKind {
  canApply,
  alreadyConnected,

  /// A non-final application exists: the duplicate is blocked here, and the
  /// server would return the same record anyway.
  activeApplication,

  /// Withdrawn / declined before. The contract derives the request id from
  /// applicant + practice, so a new create returns that old record
  /// (open question for the web team).
  appliedBefore,
  notAccepting,
}

({ApplyGuardKind kind, ConnectionRequest? existing}) applyGuard(
  ExpertProfile expert, {
  required List<ConnectionRequest> applications,
  required Set<String> connectedPsychologists,
}) {
  if (connectedPsychologists.contains(expert.id)) {
    return (kind: ApplyGuardKind.alreadyConnected, existing: null);
  }
  final mine = [
    for (final a in applications)
      if (a.psychologistUid == expert.id) a,
  ];
  final active = mine.where((a) => a.isActive).firstOrNull;
  if (active != null) {
    return (kind: ApplyGuardKind.activeApplication, existing: active);
  }
  if (mine.any((a) => a.state == ApplicationState.accepted)) {
    return (kind: ApplyGuardKind.alreadyConnected, existing: null);
  }
  if (mine.isNotEmpty) {
    return (kind: ApplyGuardKind.appliedBefore, existing: mine.first);
  }
  if (!expert.acceptingNewPatients) {
    return (kind: ApplyGuardKind.notAccepting, existing: null);
  }
  return (kind: ApplyGuardKind.canApply, existing: null);
}
