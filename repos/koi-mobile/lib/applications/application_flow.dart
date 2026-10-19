import '../care/care_session.dart';
import 'application_api.dart';
import 'application_models.dart';

/// The applicant's moves. Each one is checked against [applicantActions]
/// BEFORE any request, and the list then shows ONLY what the server
/// answered (no optimistic state).
class ApplicationFlow {
  ApplicationFlow(this.api, this.list);

  final ApplicationApi api;
  final CareList<ConnectionRequest> list;

  /// Create, then (if the server left it `requested`) continue to the demo
  /// payment step. Both keys belong to this one "Send application" action,
  /// so a retry after a timeout or a re-check repeats it safely.
  Future<ConnectionRequest> apply(
    String psychologistUid, {
    required String createKey,
    required String continueKey,
  }) async {
    final created = await api.create(
      psychologistUid,
      idempotencyKey: createKey,
    );
    list.put(created);
    if (created.state != ApplicationState.requested) return created;
    return act(
      created,
      ApplicantAction.continueToPayment,
      idempotencyKey: continueKey,
    );
  }

  Future<ConnectionRequest> act(
    ConnectionRequest r,
    ApplicantAction action, {
    required String idempotencyKey,
  }) async {
    if (!applicantActions(r.state).contains(action)) {
      throw IllegalTransitionError('${action.name} from ${r.state.wire}');
    }
    final next = await switch (action) {
      ApplicantAction.continueToPayment => api.transition(
        r.id,
        expectedRevision: r.revision,
        to: ApplicationState.awaitingDemoPayment,
        idempotencyKey: idempotencyKey,
      ),
      ApplicantAction.completeDemoPayment => api.completeDemoPayment(
        r.id,
        expectedRevision: r.revision,
        idempotencyKey: idempotencyKey,
      ),
      ApplicantAction.withdraw => api.transition(
        r.id,
        expectedRevision: r.revision,
        to: ApplicationState.withdrawn,
        idempotencyKey: idempotencyKey,
      ),
    };
    list.put(next);
    return next;
  }
}
