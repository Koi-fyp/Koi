import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_providers.dart';
import '../account/account_widgets.dart';
import '../account/capability_gate.dart';
import '../account/destinations.dart';
import '../platform/platform_client.dart';
import '../widgets/koi_loader.dart';
import '../widgets/neo_card.dart';
import 'expert_api.dart';

/// Directory list, per signed-in uid (re-fetched on account switch).
final expertListProvider = FutureProvider.autoDispose<List<ExpertProfile>>((
  ref,
) {
  final caps = ref.watch(effectiveCapabilitiesProvider);
  if (!caps.canDiscoverExperts) {
    throw const PlatformException(PlatformErrorCode.forbidden);
  }
  return ref.watch(expertDirectoryApiProvider).list();
});

final expertDetailProvider = FutureProvider.autoDispose
    .family<ExpertProfile, String>((ref, id) {
      final caps = ref.watch(effectiveCapabilitiesProvider);
      if (!caps.canDiscoverExperts) {
        throw const PlatformException(PlatformErrorCode.forbidden);
      }
      return ref.watch(expertDirectoryApiProvider).detail(id);
    });

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

/// "Find an Expert" (read-only). Applications come in a later update.
class ExpertListScreen extends StatelessWidget {
  const ExpertListScreen({super.key});

  @override
  Widget build(BuildContext context) => CapabilityGate(
    destination: KoiDestination.experts,
    builder: (_) => const _ExpertList(),
  );
}

class _ExpertList extends ConsumerWidget {
  const _ExpertList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(expertListProvider);
    final demo = ref.watch(expertDirectoryApiProvider).isMock;
    return KoiPage(
      back: true,
      demo: demo,
      title: 'Find an Expert',
      children: [
        Text(
          'Psychologists who are listed in KOI. Applying to one comes in a '
          'later update.',
          style: koiBodyStyle(),
        ),
        const SizedBox(height: 20),
        ...list.when(
          loading: () => const [NeoSkeletonList(label: 'Loading experts')],
          error: (e, _) => [
            KoiNoticeCard(
              message: platformErrorText(e),
              action: () => ref.invalidate(expertListProvider),
              actionLabel: 'Try again',
            ),
          ],
          data: (experts) => experts.isEmpty
              ? const [
                  KoiNoticeCard(message: 'No experts are listed right now.'),
                ]
              : [
                  for (final e in experts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _ExpertCard(expert: e),
                    ),
                ],
        ),
      ],
    );
  }
}

class _ExpertCard extends StatelessWidget {
  const _ExpertCard({required this.expert});
  final ExpertProfile expert;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: GestureDetector(
      key: Key('expert-${expert.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () =>
          pushKoiPage<void>(context, ExpertDetailScreen(expertId: expert.id)),
      child: NeoCard(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: koiMinTouch),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                expert.displayName,
                style: koiBodyStyle(size: 17, weight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (expert.languages.isNotEmpty) expert.languages.join(', '),
                  if (expert.modality.isNotEmpty) expert.modality,
                ].join(' · '),
                style: koiMutedStyle(),
              ),
              const SizedBox(height: 4),
              Text(
                expert.acceptingNewPatients
                    ? 'Accepting new patients'
                    : 'Not accepting new patients',
                style: koiBodyStyle(size: 13.5, weight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    ),
  );
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

class _ExpertDetail extends ConsumerWidget {
  const _ExpertDetail({required this.expertId});
  final String expertId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(expertDetailProvider(expertId));
    final demo = ref.watch(expertDirectoryApiProvider).isMock;
    return detail.when(
      loading: () =>
          const Scaffold(body: KoiLoadingPage(label: 'Loading profile…')),
      error: (e, _) => KoiPage(
        back: true,
        demo: demo,
        children: [
          KoiNoticeCard(
            message: platformErrorText(e),
            action: () => ref.invalidate(expertDetailProvider(expertId)),
            actionLabel: 'Try again',
          ),
        ],
      ),
      data: (e) => KoiPage(
        back: true,
        demo: demo,
        title: e.displayName,
        children: [
          if (e.description.isNotEmpty) ...[
            Text(e.description, style: koiBodyStyle()),
            const SizedBox(height: 16),
          ],
          NeoCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (e.languages.isNotEmpty)
                  Text(
                    'Languages: ${e.languages.join(', ')}',
                    style: koiBodyStyle(size: 14.5),
                  ),
                if (e.modality.isNotEmpty)
                  Text(
                    'Sessions: ${e.modality}',
                    style: koiBodyStyle(size: 14.5),
                  ),
                Text(
                  e.acceptingNewPatients
                      ? 'Accepting new patients'
                      : 'Not accepting new patients',
                  style: koiBodyStyle(size: 14.5, weight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const KoiNoticeCard(
            yellow: true,
            message: 'Applying to a psychologist is coming in a later update.',
          ),
        ],
      ),
    );
  }
}
