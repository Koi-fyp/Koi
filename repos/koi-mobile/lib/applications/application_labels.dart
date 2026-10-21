import 'dart:ui' show Color;

import '../account/capabilities.dart';
import '../care/care_strings.dart';
import '../theme/koi_colors.dart';
import 'application_models.dart';

// MOB-5: a mirror of the web's care-state.ts (origin/feat/koi2-ui-overhaul
// f9ed940, read with git show only). Labels only: an application never
// grants anything; patient access comes from /me/capabilities alone.

/// care-state.ts `applicationLabel`, accepted branch: the application is
/// accepted AND the confirmed capabilities list an active relationship with
/// the same practice and psychologist. Without `organization_id` (older
/// responses) the psychologist alone is matched.
bool acceptedIntoActiveCare(ConnectionRequest r, KoiCapabilities caps) =>
    r.state == ApplicationState.accepted &&
    caps.activeRelationships.any(
      (rel) =>
          rel.psychologistUid == r.psychologistUid &&
          (r.organizationId == null || rel.organizationId == r.organizationId),
    );

/// care-state.ts `applicationLabel`, word for word (CareText.state*).
String applicationLabel(
  CareStrings s,
  ConnectionRequest r,
  KoiCapabilities caps,
) => s.t(switch (r.state) {
  ApplicationState.requested => CareText.stateRequested,
  ApplicationState.awaitingDemoPayment => CareText.stateAwaitingPayment,
  ApplicationState.pendingPsychologistReview => CareText.statePendingReview,
  ApplicationState.accepted =>
    acceptedIntoActiveCare(r, caps)
        ? CareText.stateAccepted
        : CareText.m5StateAcceptedPrevious,
  ApplicationState.rejected => CareText.stateDeclined,
  ApplicationState.withdrawn => CareText.stateWithdrawn,
});

/// The helper line under an application (PatientWorkspace.tsx /
/// PracticeApplication.tsx), or null.
CareText? applicationNote(ConnectionRequest r, KoiCapabilities caps) =>
    switch (r.state) {
      ApplicationState.pendingPsychologistReview =>
        CareText.m5PendingReviewNote,
      ApplicationState.accepted =>
        acceptedIntoActiveCare(r, caps)
            ? CareText.m5AcceptedActiveNote
            : CareText.m5AcceptedPreviousNote,
      ApplicationState.rejected => CareText.declinedNote,
      _ => null,
    };

/// Mint only for care that is active now; history is grey.
Color applicationChipColor(ConnectionRequest r, KoiCapabilities caps) =>
    switch (r.state) {
      ApplicationState.accepted =>
        acceptedIntoActiveCare(r, caps) ? KoiColors.neoMint : KoiColors.neoGray,
      ApplicationState.rejected ||
      ApplicationState.withdrawn => KoiColors.neoGray,
      _ => KoiColors.neoYellow,
    };
