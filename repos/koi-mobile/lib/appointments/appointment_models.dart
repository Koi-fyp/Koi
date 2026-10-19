import 'package:flutter/foundation.dart';

import '../applications/application_models.dart' show IllegalTransitionError;
import '../care/care_api_support.dart';
import '../platform/platform_client.dart';

/// Contract v0.5.1 `AppointmentDTO.state`. Semantics (v0.5.0
/// semantics.md "Appointments"): the patient requests; the psychologist
/// proposes start/end; the patient confirms that exact proposal revision;
/// the psychologist completes a confirmed appointment after its end. The
/// psychologist may reject requested/proposed; either side may cancel
/// requested/proposed/confirmed. Terminal states never reopen.
enum AppointmentState {
  requested('requested'),
  proposed('proposed'),
  confirmed('confirmed'),
  completed('completed'),
  rejected('rejected'),
  cancelled('cancelled');

  const AppointmentState(this.wire);
  final String wire;

  static AppointmentState? fromWire(Object? v) {
    for (final s in values) {
      if (s.wire == v) return s;
    }
    return null;
  }

  bool get isTerminal =>
      this == completed || this == rejected || this == cancelled;
}

/// What the PATIENT may do. "Decline" a proposal = cancel (the contract
/// gives the patient no reject). "Ask for another time" = a NEW request
/// (the contract: "later rescheduling needs a new request"); the confirmed
/// one stays until the patient cancels it.
enum PatientAppointmentAction { confirm, cancel, askAnotherTime }

Set<PatientAppointmentAction> patientAppointmentActions(Appointment a) =>
    switch (a.state) {
      AppointmentState.requested => const {PatientAppointmentAction.cancel},
      AppointmentState.proposed => {
        if (a.startsAt != null && a.endsAt != null)
          PatientAppointmentAction.confirm,
        PatientAppointmentAction.cancel,
      },
      AppointmentState.confirmed => const {
        PatientAppointmentAction.cancel,
        PatientAppointmentAction.askAnotherTime,
      },
      _ => const {},
    };

/// The only `to_state` values the patient app ever sends, and from where.
bool isLegalPatientTransition(AppointmentState from, AppointmentState to) =>
    switch (to) {
      AppointmentState.confirmed => from == AppointmentState.proposed,
      AppointmentState.cancelled =>
        from == AppointmentState.requested ||
            from == AppointmentState.proposed ||
            from == AppointmentState.confirmed,
      _ => false,
    };

void checkPatientTransition(AppointmentState from, AppointmentState to) {
  if (!isLegalPatientTransition(from, to)) {
    throw IllegalTransitionError('${from.wire} → ${to.wire}');
  }
}

@immutable
class Appointment {
  const Appointment({
    required this.id,
    required this.relationshipId,
    required this.state,
    required this.revision,
    required this.updatedAt,
    this.startsAt,
    this.endsAt,
  });

  final String id;
  final String relationshipId;
  final AppointmentState state;
  final int revision;
  final DateTime updatedAt;
  final DateTime? startsAt;
  final DateTime? endsAt;

  factory Appointment.fromJson(Object? v) {
    final j = asJsonMap(v, 'appointment');
    final state = AppointmentState.fromWire(j['state']);
    if (state == null) throw const FormatException('Unknown state');
    return Appointment(
      id: reqString(j, 'id'),
      relationshipId: reqString(j, 'relationship_id'),
      state: state,
      revision: reqInt(j, 'revision'),
      updatedAt: reqTime(j, 'updated_at'),
      startsAt: optTime(j, 'starts_at'),
      endsAt: optTime(j, 'ends_at'),
    );
  }
}

enum AppointmentSection { upcoming, pending, past, cancelled }

/// Upcoming = confirmed; Pending = requested + proposed; Past = completed;
/// Cancelled = cancelled + rejected.
AppointmentSection sectionOf(Appointment a) => switch (a.state) {
  AppointmentState.confirmed => AppointmentSection.upcoming,
  AppointmentState.requested ||
  AppointmentState.proposed => AppointmentSection.pending,
  AppointmentState.completed => AppointmentSection.past,
  AppointmentState.cancelled ||
  AppointmentState.rejected => AppointmentSection.cancelled,
};
