import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_providers.dart';
import '../app/providers.dart';
import '../platform/platform_client.dart';
import '../platform/platform_config.dart';
import 'asset_manifest.dart';
import 'attempt_controller.dart';
import 'draft_store.dart';
import 'mock_questionnaire_api.dart';
import 'questionnaire_api.dart';
import 'questionnaire_models.dart';

/// Overridden in main.dart with the `koi_questionnaire_drafts` Hive box.
final draftBoxProvider = Provider<DraftBox>((ref) => MemoryDraftBox());

final draftRepositoryProvider = Provider<DraftRepository>(
  (ref) => DraftRepository(
    box: ref.read(draftBoxProvider),
    cipher: ref.read(messageCipherProvider),
    cryptoContext: ref.read(cryptoContextGetterProvider),
  ),
);

/// A new adapter per signed-in uid, so nothing (not even demo data) is
/// shared between accounts. Mock (KOI_MOCKS) > real > unavailable.
final questionnaireApiProvider = Provider<QuestionnaireApi>((ref) {
  ref.watch(authServiceProvider.select((a) => a.user?.uid));
  if (koiMocksEnabled) {
    return MockQuestionnaireRemote(latency: const Duration(milliseconds: 400));
  }
  final client = ref.read(platformClientProvider);
  return client.isConfigured
      ? HttpQuestionnaireApi(client)
      : const UnavailableQuestionnaireApi();
});

final questionnaireAssetManifestProvider =
    FutureProvider<QuestionnaireAssetManifest>(
      (ref) => QuestionnaireAssetManifest.load(),
    );

/// The patient's assigned questionnaires; refused without the confirmed
/// questionnaire capability of the current uid.
final assignmentsProvider = FutureProvider.autoDispose<List<Assignment>>((ref) {
  final caps = ref.watch(effectiveCapabilitiesProvider);
  ref.watch(authServiceProvider.select((a) => a.user?.uid));
  if (!caps.canUseQuestionnaires) {
    throw const PlatformException(PlatformErrorCode.forbidden);
  }
  return ref.watch(questionnaireApiProvider).assignments();
});

/// Identifies one attempt of one account.
@immutable
class AttemptRef {
  const AttemptRef(this.uid, this.assignment);
  final String uid;
  final Assignment assignment;

  @override
  bool operator ==(Object other) =>
      other is AttemptRef &&
      other.uid == uid &&
      other.assignment.attemptId == assignment.attemptId &&
      other.assignment.versionId == assignment.versionId;

  @override
  int get hashCode =>
      Object.hash(uid, assignment.attemptId, assignment.versionId);
}

/// Disposed with its screen: a pending autosave timer dies with it.
final attemptControllerProvider = ChangeNotifierProvider.autoDispose
    .family<AttemptController, AttemptRef>((ref, r) {
      final controller = AttemptController(
        uid: r.uid,
        assignment: r.assignment,
        api: ref.read(questionnaireApiProvider),
        drafts: ref.read(draftRepositoryProvider),
        onlineChanges: ref.read(onlineStatusProvider).changes,
      );
      controller.load();
      return controller;
    });

/// Registers the questionnaire caches with the account cleanup (read once
/// by the root): drafts go on sign-out and when the relationship ends.
final questionnaireCleanupProvider = Provider<void>((ref) {
  final cleanup = ref.read(accountCleanupProvider);
  final drafts = ref.read(draftRepositoryProvider);
  cleanup
    ..onSignOut(drafts.deleteAllFor)
    ..onPatientAccessLost((uid) async {
      await drafts.deleteAllFor(uid);
      ref.invalidate(assignmentsProvider);
    });
});
