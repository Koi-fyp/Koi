import 'package:flutter/foundation.dart';

import '../care/care_api_support.dart';
import '../platform/platform_client.dart';

/// Contract v0.5.1 `ConnectionRequestDTO.state` (the web calls these
/// "applications"). The server owns every transition
/// (origin/feat/web-1-professional-publishing lifecycle.ts:173).
enum ApplicationState {
  requested('requested'),
  awaitingDemoPayment('awaiting_demo_payment'),
  pendingPsychologistReview('pending_psychologist_review'),
  accepted('accepted'),

  /// Shown as "Declined".
  rejected('rejected'),
  withdrawn('withdrawn');

  const ApplicationState(this.wire);
  final String wire;

  static ApplicationState? fromWire(Object? v) {
    for (final s in values) {
      if (s.wire == v) return s;
    }
    return null;
  }

  bool get isTerminal =>
      this == accepted || this == rejected || this == withdrawn;
}

/// What the APPLICANT may do in each state (lifecycle.ts:185-189):
/// - requested → awaiting_demo_payment ("Continue") or withdrawn;
/// - awaiting_demo_payment → demo-payment action, or withdrawn;
/// - pending_psychologist_review → withdrawn (the psychologist decides);
/// - accepted / rejected / withdrawn → nothing.
enum ApplicantAction { continueToPayment, completeDemoPayment, withdraw }

Set<ApplicantAction> applicantActions(ApplicationState s) => switch (s) {
  ApplicationState.requested => const {
    ApplicantAction.continueToPayment,
    ApplicantAction.withdraw,
  },
  ApplicationState.awaitingDemoPayment => const {
    ApplicantAction.completeDemoPayment,
    ApplicantAction.withdraw,
  },
  ApplicationState.pendingPsychologistReview => const {
    ApplicantAction.withdraw,
  },
  _ => const {},
};

/// Thrown before any request when the UI would ask for a move the
/// applicant cannot make: the call never reaches the server.
class IllegalTransitionError extends StateError {
  IllegalTransitionError(super.message);
}

/// `demo_payment_state`: SIMULATED ONLY. No card, no gateway.
enum DemoPaymentState { pending, completed }

@immutable
class ConnectionRequest {
  const ConnectionRequest({
    required this.id,
    required this.psychologistUid,
    required this.state,
    required this.demoPayment,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    this.organizationId,
  });

  final String id;
  final String psychologistUid;

  /// MOB-5: `organization_id`, read only to match an accepted application
  /// to an active relationship (care-state.ts applicationLabel). Optional
  /// and tolerant: absent, empty or not a string → null.
  final String? organizationId;
  final ApplicationState state;
  final DemoPaymentState demoPayment;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isActive => !state.isTerminal;

  /// Whitelisted fields only; an unknown state is a format error (the list
  /// skips it).
  factory ConnectionRequest.fromJson(Object? v) {
    final j = asJsonMap(v, 'connection request');
    final state = ApplicationState.fromWire(j['state']);
    if (state == null) throw const FormatException('Unknown state');
    return ConnectionRequest(
      id: reqString(j, 'id'),
      psychologistUid: reqString(j, 'psychologist_uid'),
      state: state,
      demoPayment: j['demo_payment_state'] == 'demo_completed'
          ? DemoPaymentState.completed
          : DemoPaymentState.pending,
      revision: reqInt(j, 'revision'),
      createdAt: reqTime(j, 'created_at'),
      updatedAt: reqTime(j, 'updated_at'),
      organizationId: switch (j['organization_id']) {
        final String o when o.isNotEmpty => o,
        _ => null,
      },
    );
  }
}
