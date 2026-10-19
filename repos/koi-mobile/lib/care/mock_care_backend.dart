import 'package:flutter/foundation.dart';

import '../account/capabilities.dart';
import '../applications/application_api.dart';
import '../applications/application_models.dart';
import '../appointments/appointment_api.dart';
import '../appointments/appointment_models.dart';
import '../care_messages/message_api.dart';
import '../care_messages/message_models.dart';
import '../experts/expert_api.dart';
import '../notifications/notification_api.dart';
import '../notifications/notification_models.dart';
import '../platform/platform_client.dart';
import 'care_api_support.dart';

/// KOI_MOCKS=true ONLY: an in-memory stand-in for the platform server so
/// the MOB-2 flows can be tried on a phone. Every screen fed by it shows
/// the "Demo data" badge. It follows the contract v0.5.1 rules (states,
/// revisions, one request per psychologist, fixed notification kinds) and
/// keeps each signed-in uid's data apart.
///
/// The psychologist's side (accept, propose a time, reply, end the
/// relationship) is driven from the debug-only "Simulate psychologist"
/// menu (kDebugMode AND KOI_MOCKS).
class MockCareBackend extends ChangeNotifier {
  MockCareBackend({
    required this.currentUid,
    this.capabilities,
    this.latency = const Duration(milliseconds: 400),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final String? Function() currentUid;

  /// The mock capabilities: acceptance / closure changes them, like the
  /// real server's relationship records do.
  final MockCapabilitiesSource? capabilities;
  final Duration latency;
  final DateTime Function() _now;

  final Map<String, _UserData> _users = {};
  int _seq = 0;

  _UserData get _me {
    final uid = currentUid();
    if (uid == null) {
      throw const PlatformException(PlatformErrorCode.unauthorized);
    }
    return _users.putIfAbsent(uid, _UserData.new);
  }

  DateTime get _t => _now().toUtc();
  String _id(String p) => '$p-${++_seq}';

  Future<void> _wait() => Future<void>.delayed(latency);

  static const PlatformException _conflict = PlatformException(
    PlatformErrorCode.conflict,
    status: 409,
    body: {'code': 'conflict', 'request_id': 'mock', 'retryable': false},
  );
  static const PlatformException _notFound = PlatformException(
    PlatformErrorCode.notFound,
    status: 404,
    body: {'code': 'not_found', 'request_id': 'mock', 'retryable': false},
  );

  /// The relationship the mock capabilities currently report (the MOB-1
  /// role picker's "patient" uses MockCapabilitiesSource.demoRelationship).
  RelationshipSummary? get _relationship {
    final c = capabilities;
    if (c == null || c.role.value != KoiRole.patient) return null;
    return c.relationship;
  }

  void _notify(_UserData u, NotificationKind kind, String referenceId) {
    final id = _id('demo-notification');
    u.notifications.insert(
      0,
      CareNotification(
        id: id,
        eventId: 'event-$id',
        kind: kind,
        referenceId: referenceId,
        createdAt: _t,
      ),
    );
    notifyListeners();
  }

  // ---- applications ----

  Future<ApiPage<ConnectionRequest>> listApplications() async {
    await _wait();
    return ApiPage(_me.applications.values.toList(), null);
  }

  Future<ConnectionRequest> createApplication(String psychologistUid) async {
    await _wait();
    final u = _me;
    if (_relationship?.psychologistUid == psychologistUid) throw _conflict;
    // Like the server: one request id per applicant + practice; a second
    // create returns the existing record.
    final id = 'demo-request-$psychologistUid';
    return u.applications.putIfAbsent(
      id,
      () => ConnectionRequest(
        id: id,
        psychologistUid: psychologistUid,
        state: ApplicationState.requested,
        demoPayment: DemoPaymentState.pending,
        revision: 1,
        createdAt: _t,
        updatedAt: _t,
      ),
    );
  }

  Future<ConnectionRequest> transitionApplication(
    String id,
    int expectedRevision,
    ApplicationState to, {
    bool demoPayment = false,
  }) async {
    await _wait();
    final u = _me;
    final r = u.applications[id];
    if (r == null) throw _notFound;
    if (r.revision != expectedRevision) throw _conflict;
    final ok = demoPayment
        ? r.state == ApplicationState.awaitingDemoPayment
        : switch (to) {
            ApplicationState.awaitingDemoPayment =>
              r.state == ApplicationState.requested,
            ApplicationState.withdrawn => !r.state.isTerminal,
            _ => false,
          };
    if (!ok) throw _conflict;
    return u.applications[id] = _copy(
      r,
      demoPayment ? ApplicationState.pendingPsychologistReview : to,
      demoPayment: demoPayment ? DemoPaymentState.completed : null,
    );
  }

  ConnectionRequest _copy(
    ConnectionRequest r,
    ApplicationState s, {
    DemoPaymentState? demoPayment,
  }) => ConnectionRequest(
    id: r.id,
    psychologistUid: r.psychologistUid,
    state: s,
    demoPayment: demoPayment ?? r.demoPayment,
    revision: r.revision + 1,
    createdAt: r.createdAt,
    updatedAt: _t,
  );

  // ---- simulated psychologist (debug menu) ----

  /// Applications waiting for the psychologist's decision.
  List<ConnectionRequest> get awaitingDecision => [
    for (final r in _me.applications.values)
      if (r.state == ApplicationState.pendingPsychologistReview) r,
  ];

  void simulateDecision(String requestId, {required bool accept}) {
    final u = _me;
    final r = u.applications[requestId];
    if (r == null || r.state != ApplicationState.pendingPsychologistReview) {
      return;
    }
    u.applications[requestId] = _copy(
      r,
      accept ? ApplicationState.accepted : ApplicationState.rejected,
    );
    if (accept) {
      final c = capabilities;
      if (c != null) {
        c.relationship = RelationshipSummary(
          id: 'demo-relationship-${r.psychologistUid}',
          active: true,
          organizationId: 'demo-org-${r.psychologistUid}',
          psychologistUid: r.psychologistUid,
        );
        c.role.value = KoiRole.patient;
      }
    }
    _notify(u, NotificationKind.applicationState, requestId);
  }

  void simulateReply(String text) {
    final rel = _relationship;
    if (rel == null) return;
    final m = HumanMessage(
      id: _id('demo-message'),
      relationshipId: rel.id,
      senderUid: rel.psychologistUid,
      body: text,
      createdAt: _t,
    );
    _me.messages.putIfAbsent(rel.id, () => []).add(m);
    _notify(_me, NotificationKind.newMessage, m.id);
  }

  /// Proposes tomorrow 10:00–10:50 local time for the newest request.
  void simulateProposeTime() {
    final rel = _relationship;
    if (rel == null) return;
    final list = _me.appointments[rel.id] ?? const <Appointment>[];
    final i = list.indexWhere((a) => a.state == AppointmentState.requested);
    if (i < 0) return;
    final local = _now().add(const Duration(days: 1));
    final start = DateTime(local.year, local.month, local.day, 10);
    _me.appointments[rel.id]![i] = _appt(
      list[i],
      AppointmentState.proposed,
      start: start.toUtc(),
      end: start.add(const Duration(minutes: 50)).toUtc(),
    );
    _notify(_me, NotificationKind.appointmentChange, list[i].id);
  }

  void simulateCompleteConfirmed() {
    final rel = _relationship;
    if (rel == null) return;
    final list = _me.appointments[rel.id] ?? const <Appointment>[];
    final i = list.indexWhere((a) => a.state == AppointmentState.confirmed);
    if (i < 0) return;
    _me.appointments[rel.id]![i] = _appt(list[i], AppointmentState.completed);
    _notify(_me, NotificationKind.appointmentChange, list[i].id);
  }

  void simulateQuestionnaireAssigned() {
    if (_relationship == null) return;
    _notify(_me, NotificationKind.assignment, 'demo-assignment-1');
  }

  /// The psychologist closes the relationship: the mock capabilities drop
  /// the patient role, like the server's closure (no notification kind
  /// exists for this; the app learns it from /me/capabilities).
  void simulateEndRelationship() {
    final c = capabilities;
    if (c == null) return;
    c.role.value = KoiRole.general;
    c.relationship = MockCapabilitiesSource.demoRelationship;
    notifyListeners();
  }

  // ---- messages ----

  Future<ApiPage<HumanMessage>> listMessages(String relationshipId) async {
    await _wait();
    _requireRelationship(relationshipId);
    return ApiPage([...?_me.messages[relationshipId]], null);
  }

  Future<HumanMessage> sendMessage(String relationshipId, String body) async {
    await _wait();
    _requireRelationship(relationshipId);
    final m = HumanMessage(
      id: _id('demo-message'),
      relationshipId: relationshipId,
      senderUid: currentUid()!,
      body: body,
      createdAt: _t,
    );
    _me.messages.putIfAbsent(relationshipId, () => []).add(m);
    return m;
  }

  // ---- appointments ----

  Future<ApiPage<Appointment>> listAppointments(String relationshipId) async {
    await _wait();
    _requireRelationship(relationshipId);
    return ApiPage([...?_me.appointments[relationshipId]], null);
  }

  Future<Appointment> requestAppointment(String relationshipId) async {
    await _wait();
    _requireRelationship(relationshipId);
    final a = Appointment(
      id: _id('demo-appointment'),
      relationshipId: relationshipId,
      state: AppointmentState.requested,
      revision: 1,
      updatedAt: _t,
    );
    _me.appointments.putIfAbsent(relationshipId, () => []).add(a);
    return a;
  }

  Future<Appointment> transitionAppointment(
    String id,
    int expectedRevision,
    AppointmentState to,
  ) async {
    await _wait();
    for (final list in _me.appointments.values) {
      final i = list.indexWhere((a) => a.id == id);
      if (i < 0) continue;
      final a = list[i];
      _requireRelationship(a.relationshipId);
      if (a.revision != expectedRevision ||
          !isLegalPatientTransition(a.state, to)) {
        throw _conflict;
      }
      return list[i] = _appt(a, to);
    }
    throw _notFound;
  }

  Appointment _appt(
    Appointment a,
    AppointmentState s, {
    DateTime? start,
    DateTime? end,
  }) => Appointment(
    id: a.id,
    relationshipId: a.relationshipId,
    state: s,
    revision: a.revision + 1,
    updatedAt: _t,
    startsAt: start ?? a.startsAt,
    endsAt: end ?? a.endsAt,
  );

  void _requireRelationship(String relationshipId) {
    if (_relationship?.id != relationshipId) {
      throw const PlatformException(
        PlatformErrorCode.forbidden,
        status: 403,
        body: {'code': 'forbidden', 'request_id': 'mock', 'retryable': false},
      );
    }
  }

  // ---- notifications ----

  Future<ApiPage<CareNotification>> listNotifications() async {
    await _wait();
    final u = _me;
    final patient = _relationship != null;
    // Closure redacts relationship-scoped notifications from later reads.
    return ApiPage([
      for (final n in u.notifications)
        if (patient || n.kind == NotificationKind.applicationState) n,
    ], null);
  }

  Future<CareNotification> markNotificationRead(String id) async {
    await _wait();
    final u = _me;
    final i = u.notifications.indexWhere((n) => n.id == id);
    if (i < 0) throw _notFound;
    final n = u.notifications[i];
    return u.notifications[i] = n.isRead ? n : n.markedRead(_t);
  }
}

class _UserData {
  final Map<String, ConnectionRequest> applications = {};
  final Map<String, List<HumanMessage>> messages = {};
  final Map<String, List<Appointment>> appointments = {};
  final List<CareNotification> notifications = [];
}

class MockApplicationApi implements ApplicationApi {
  MockApplicationApi(this.backend);
  final MockCareBackend backend;

  @override
  bool get isMock => true;
  @override
  Future<ApiPage<ConnectionRequest>> list({String? cursor}) =>
      backend.listApplications();
  @override
  Future<ConnectionRequest> create(
    String psychologistUid, {
    required String idempotencyKey,
  }) => backend.createApplication(psychologistUid);
  @override
  Future<ConnectionRequest> transition(
    String id, {
    required int expectedRevision,
    required ApplicationState to,
    required String idempotencyKey,
  }) => backend.transitionApplication(id, expectedRevision, to);
  @override
  Future<ConnectionRequest> completeDemoPayment(
    String id, {
    required int expectedRevision,
    required String idempotencyKey,
  }) => backend.transitionApplication(
    id,
    expectedRevision,
    ApplicationState.pendingPsychologistReview,
    demoPayment: true,
  );
}

class MockCareMessageApi implements CareMessageApi {
  MockCareMessageApi(this.backend);
  final MockCareBackend backend;

  @override
  bool get isMock => true;
  @override
  Future<ApiPage<HumanMessage>> list(String relationshipId, {String? cursor}) =>
      backend.listMessages(relationshipId);
  @override
  Future<HumanMessage> send(
    String relationshipId,
    String body, {
    required String idempotencyKey,
  }) => backend.sendMessage(relationshipId, body);
}

class MockAppointmentApi implements AppointmentApi {
  MockAppointmentApi(this.backend);
  final MockCareBackend backend;

  @override
  bool get isMock => true;
  @override
  Future<ApiPage<Appointment>> list(String relationshipId, {String? cursor}) =>
      backend.listAppointments(relationshipId);
  @override
  Future<Appointment> request(
    String relationshipId, {
    required String idempotencyKey,
  }) => backend.requestAppointment(relationshipId);
  @override
  Future<Appointment> transition(
    String id, {
    required int expectedRevision,
    required AppointmentState to,
    required String idempotencyKey,
  }) => backend.transitionAppointment(id, expectedRevision, to);
}

class MockNotificationApi implements NotificationApi {
  MockNotificationApi(this.backend);
  final MockCareBackend backend;

  @override
  bool get isMock => true;
  @override
  Future<ApiPage<CareNotification>> list({String? cursor}) =>
      backend.listNotifications();
  @override
  Future<CareNotification> markRead(
    String id, {
    required String idempotencyKey,
  }) => backend.markNotificationRead(id);
}

/// The demo directory, for the simulate menu's names.
String mockExpertName(String uid) => MockExpertDirectoryApi.profiles
    .firstWhere(
      (p) => p.id == uid,
      orElse: () => ExpertProfile(
        id: uid,
        displayName: uid,
        bio: '',
        acceptingNewPatients: false,
      ),
    )
    .displayName;
