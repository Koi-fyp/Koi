import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/account/capabilities.dart';
import 'package:koi_mobile/applications/application_api.dart';
import 'package:koi_mobile/applications/application_models.dart';
import 'package:koi_mobile/appointments/appointment_api.dart';
import 'package:koi_mobile/appointments/appointment_models.dart';
import 'package:koi_mobile/app/root_router.dart';
import 'package:koi_mobile/care/care_api_support.dart';
import 'package:koi_mobile/care/care_providers.dart';
import 'package:koi_mobile/care/mock_care_backend.dart';
import 'package:koi_mobile/care_messages/message_api.dart';
import 'package:koi_mobile/care_messages/message_models.dart';
import 'package:koi_mobile/chat/chat_api.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/experts/expert_api.dart';
import 'package:koi_mobile/notifications/notification_api.dart';
import 'package:koi_mobile/notifications/notification_models.dart';
import 'package:koi_mobile/platform/platform_client.dart';
import 'package:koi_mobile/questionnaires/questionnaire_api.dart';
import 'package:koi_mobile/settings/settings_prefs.dart';

import 'mob1_fakes.dart';

/// A MOB-1 harness plus the demo care backend wired as the MOB-2 adapters
/// (like KOI_MOCKS=true), with MockCapabilitiesSource so an accepted demo
/// application really turns the account into a Patient.
class Mob2Harness {
  Mob2Harness({
    required KoiUser user,
    KoiRole role = KoiRole.general,
    Duration latency = Duration.zero,
    this.simulateMenu,
    ChatApiClient? chatApi,
    ExpertDirectoryApi? experts,
    QuestionnaireApi? questionnaires,
  }) : caps = MockCapabilitiesSource(initial: role) {
    counting = CountingCapabilities(caps);
    base = Mob1Harness(
      user: user,
      capabilities: counting,
      experts: experts ?? MockExpertDirectoryApi(latency: latency, pageSize: 2),
      chatApi: chatApi,
      questionnaires: questionnaires,
    );
    backend = MockCareBackend(
      currentUid: () => base.auth.user?.uid,
      capabilities: caps,
      latency: latency,
    );
  }

  final MockCapabilitiesSource caps;
  late final CountingCapabilities counting;

  /// null = the real provider (kDebugMode AND KOI_MOCKS → false in tests).
  final bool? simulateMenu;
  late final Mob1Harness base;
  late final MockCareBackend backend;

  /// Swappable per test (error / gated fakes).
  ApplicationApi? applicationApi;
  CareMessageApi? messageApi;
  AppointmentApi? appointmentApi;
  NotificationApi? notificationApi;

  AccountFakeAuth get auth => base.auth;

  void urdu(String uid) =>
      base.settings.values[uid] = const SettingsPrefs(language: 'ur');

  List<Override> get overrides => [
    ...base.overrides,
    mockCareBackendProvider.overrideWithValue(backend),
    applicationApiProvider.overrideWithValue(
      applicationApi ?? MockApplicationApi(backend),
    ),
    careMessageApiProvider.overrideWithValue(
      messageApi ?? MockCareMessageApi(backend),
    ),
    appointmentApiProvider.overrideWithValue(
      appointmentApi ?? MockAppointmentApi(backend),
    ),
    notificationApiProvider.overrideWithValue(
      notificationApi ?? MockNotificationApi(backend),
    ),
    if (simulateMenu != null)
      simulatePsychologistMenuProvider.overrideWithValue(simulateMenu!),
  ];
}

/// 360 x 800 dp, RootRouter, two short pumps (no pumpAndSettle: KoiLoader
/// animates forever).
Future<void> pumpKoi(
  WidgetTester tester,
  List<Override> overrides, {
  Widget home = const RootRouter(),
  double width = 360,
}) async {
  tester.view.physicalSize = Size(width * 3, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: home),
    ),
  );
  await settle(tester);
}

/// Lets fake async work (mock latency 0, page transitions 0.5 s) finish.
Future<void> settle(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder navTab(String name) => find.byKey(Key('nav-tab-$name'));

Future<void> tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await revealKey(tester, key);
  await tester.ensureVisible(f);
  // MOB-5: the jump is laid out on the next frame (rows below the fold).
  await tester.pump();
  await tester.tap(f);
  await settle(tester);
}

/// MOB-5: the Care hubs are taller, so a row further down may not be
/// built yet (lazy list). Scrolls the top page's list until it is.
Future<void> revealKey(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  if (f.evaluate().isNotEmpty) return;
  await tester.scrollUntilVisible(
    f,
    200,
    scrollable: find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .last,
  );
}

/// A script for one fake call: optional gate (holds the call) and error.
class CallScript {
  Completer<void>? gate;
  Object? error;

  /// Thrown by the next call only.
  Object? errorOnce;
  int calls = 0;

  Future<T> run<T>(T Function() value) async {
    calls++;
    final g = gate;
    if (g != null) await g.future;
    final once = errorOnce;
    if (once != null) {
      errorOnce = null;
      throw once;
    }
    final e = error;
    if (e != null) throw e;
    return value();
  }
}

/// Counts capability fetches (proves a re-check did / did not happen).
class CountingCapabilities implements CapabilitiesSource {
  CountingCapabilities(this.inner);
  final CapabilitiesSource inner;
  int fetches = 0;

  @override
  bool get isMock => inner.isMock;

  @override
  Future<KoiCapabilities> fetch(String uid) {
    fetches++;
    return inner.fetch(uid);
  }
}

const PlatformException offlineError = PlatformException(
  PlatformErrorCode.network,
);
const PlatformException forbiddenError = PlatformException(
  PlatformErrorCode.forbidden,
  status: 403,
  body: {'code': 'forbidden', 'request_id': 'r', 'retryable': false},
);
const PlatformException reauthError = PlatformException(
  PlatformErrorCode.reauthRequired,
  status: 401,
  body: {'code': 'unauthenticated', 'request_id': 'r', 'retryable': false},
);

class FakeNotificationApi implements NotificationApi {
  final CallScript listScript = CallScript();
  List<CareNotification> items = [];

  @override
  bool get isMock => false;

  @override
  Future<ApiPage<CareNotification>> list({String? cursor}) =>
      listScript.run(() => ApiPage([...items], null));

  @override
  Future<CareNotification> markRead(
    String id, {
    required String idempotencyKey,
  }) async {
    final i = items.indexWhere((n) => n.id == id);
    return items[i] = items[i].markedRead(DateTime.utc(2026, 10, 19));
  }
}

class FakeApplicationApi implements ApplicationApi {
  final CallScript listScript = CallScript();
  final CallScript mutateScript = CallScript();
  List<ConnectionRequest> items = [];
  final keys = <String>[];

  @override
  bool get isMock => false;

  @override
  Future<ApiPage<ConnectionRequest>> list({String? cursor}) =>
      listScript.run(() => ApiPage([...items], null));

  @override
  Future<ConnectionRequest> create(
    String psychologistUid, {
    required String idempotencyKey,
  }) {
    keys.add(idempotencyKey);
    return mutateScript.run(
      () => items.firstWhere(
        (r) => r.psychologistUid == psychologistUid,
        orElse: () {
          final r = request('req-$psychologistUid', psychologistUid);
          items.add(r);
          return r;
        },
      ),
    );
  }

  @override
  Future<ConnectionRequest> transition(
    String id, {
    required int expectedRevision,
    required ApplicationState to,
    required String idempotencyKey,
  }) {
    keys.add(idempotencyKey);
    return mutateScript.run(() => _set(id, to));
  }

  @override
  Future<ConnectionRequest> completeDemoPayment(
    String id, {
    required int expectedRevision,
    required String idempotencyKey,
  }) {
    keys.add(idempotencyKey);
    return mutateScript.run(
      () => _set(id, ApplicationState.pendingPsychologistReview, paid: true),
    );
  }

  ConnectionRequest _set(String id, ApplicationState s, {bool paid = false}) {
    final i = items.indexWhere((r) => r.id == id);
    final r = items[i];
    return items[i] = ConnectionRequest(
      id: r.id,
      psychologistUid: r.psychologistUid,
      state: s,
      demoPayment: paid ? DemoPaymentState.completed : r.demoPayment,
      revision: r.revision + 1,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
    );
  }
}

ConnectionRequest request(
  String id,
  String psychologistUid, {
  ApplicationState state = ApplicationState.requested,
  int revision = 1,
}) => ConnectionRequest(
  id: id,
  psychologistUid: psychologistUid,
  state: state,
  demoPayment: DemoPaymentState.pending,
  revision: revision,
  createdAt: DateTime.utc(2026, 10, 19, 8),
  updatedAt: DateTime.utc(2026, 10, 19, 8),
);

class FakeMessageApi implements CareMessageApi {
  final CallScript listScript = CallScript();
  final CallScript sendScript = CallScript();
  final Map<String, List<HumanMessage>> byRelationship = {};
  final sentKeys = <String>[];

  @override
  bool get isMock => false;

  @override
  Future<ApiPage<HumanMessage>> list(String relationshipId, {String? cursor}) =>
      listScript.run(() => ApiPage([...?byRelationship[relationshipId]], null));

  @override
  Future<HumanMessage> send(
    String relationshipId,
    String body, {
    required String idempotencyKey,
  }) {
    sentKeys.add(idempotencyKey);
    return sendScript.run(() {
      final m = HumanMessage(
        id: 'm-${sentKeys.length}',
        relationshipId: relationshipId,
        senderUid: 'me',
        body: body,
        createdAt: DateTime.utc(2026, 10, 19, 9, sentKeys.length),
      );
      byRelationship.putIfAbsent(relationshipId, () => []).add(m);
      return m;
    });
  }
}

class FakeAppointmentApi implements AppointmentApi {
  final CallScript listScript = CallScript();
  final CallScript mutateScript = CallScript();
  List<Appointment> items = [];
  final calls = <String>[];

  @override
  bool get isMock => false;

  @override
  Future<ApiPage<Appointment>> list(String relationshipId, {String? cursor}) =>
      listScript.run(() => ApiPage([...items], null));

  @override
  Future<Appointment> request(
    String relationshipId, {
    required String idempotencyKey,
  }) {
    calls.add('request');
    return mutateScript.run(() {
      final a = appointment(
        'a-${items.length + 1}',
        AppointmentState.requested,
      );
      items.add(a);
      return a;
    });
  }

  @override
  Future<Appointment> transition(
    String id, {
    required int expectedRevision,
    required AppointmentState to,
    required String idempotencyKey,
  }) {
    calls.add('${to.wire}:$id');
    return mutateScript.run(() {
      final i = items.indexWhere((a) => a.id == id);
      final a = items[i];
      return items[i] = Appointment(
        id: a.id,
        relationshipId: a.relationshipId,
        state: to,
        revision: a.revision + 1,
        updatedAt: a.updatedAt,
        startsAt: a.startsAt,
        endsAt: a.endsAt,
      );
    });
  }
}

Appointment appointment(
  String id,
  AppointmentState state, {
  String relationshipId = 'rel-1',
  DateTime? start,
}) => Appointment(
  id: id,
  relationshipId: relationshipId,
  state: state,
  revision: 1,
  updatedAt: DateTime.utc(2026, 10, 19, 8),
  startsAt: start,
  endsAt: start?.add(const Duration(minutes: 50)),
);

CareNotification note(
  String id,
  NotificationKind kind,
  String ref, {
  bool read = false,
}) => CareNotification(
  id: id,
  eventId: 'e-$id',
  kind: kind,
  referenceId: ref,
  createdAt: DateTime.utc(2026, 10, 19, 7),
  readAt: read ? DateTime.utc(2026, 10, 19, 8) : null,
);

/// Records every request; answers with [reply] (method + path → response).
class RecordingTransport implements PlatformTransport {
  RecordingTransport(this.reply);
  final PlatformHttpResponse Function(String method, Uri uri) reply;
  final requests =
      <({String method, Uri uri, Map<String, String> headers, String? body})>[];

  @override
  Future<PlatformHttpResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async {
    requests.add((method: method, uri: uri, headers: headers, body: body));
    return reply(method, uri);
  }
}

PlatformClient recordingClient(
  RecordingTransport t, {
  void Function()? onForbidden,
}) => PlatformClient(
  base: Uri.parse('https://platform.test'),
  transport: t,
  idToken: () async => 'tok',
  refreshIdToken: () async => 'tok2',
  onForbidden: onForbidden,
);

PlatformHttpResponse json200(Object body) =>
    PlatformHttpResponse(200, jsonEncode(body));

/// The patient fixture with contract-style ids (no display name).
const RelationshipSummary rel1 = RelationshipSummary(
  id: 'rel-1',
  active: true,
  organizationId: 'org-1',
  psychologistUid: 'demo-expert-1',
);

const KoiCapabilities contractPatientCaps = KoiCapabilities(
  role: KoiRole.patient,
  expertDiscovery: true,
  questionnaires: true,
  relationship: rel1,
  relationships: [rel1],
);
